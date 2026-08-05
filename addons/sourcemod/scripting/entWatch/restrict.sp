#define SELECT_SUMM_BANS    "SELECT COUNT(`pid`), SUM(`duration`) FROM `ebans` WHERE (`pid` = %i OR `pip` = '%s');"
#define INSERT_BAN          "INSERT INTO `ebans` (`pid`, `pname`, `pip`, `aid`, `aname`, `duration`, `expires`) VALUES (%i, '%s', '%s', %i, '%s', %i, %i);"
#define DELETE_BAN          "DELETE FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND (`pid` = %i OR `pip` = '%s')"
#define INSERT_ADD_BAN      "INSERT INTO `ebans` (`pid`, `pip`, `aid`, `aname`, `duration`, `expires`) VALUES (%i, '%s', %i, '%s', %i, %i);"

#define SELECT_BAN_ID_IP    "SELECT `pid` FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND (`pid` = %i AND `pip` = '%s') LIMIT 1;"
#define SELECT_BAN_ID       "SELECT `pid` FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND `pid` = %i LIMIT 1;"
#define SELECT_BAN_IP       "SELECT `pid` FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND `pip` = '%s' LIMIT 1;"

#define DELETE_BAN_ID_IP    "DELETE FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND (`pid` = %i AND `pip` = '%s');"
#define DELETE_BAN_ID       "DELETE FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND `pid` = %i;"
#define DELETE_BAN_IP       "DELETE FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND `pip` = '%s';"

enum struct Restrict
{
    int Count;
    int TotalDuration;

    // Current restrict
    int Admin;
    int Duration;
    int Expires;

    // Кэш членства в TempRestricts[]. Не источник истины, а производная от него:
    // прочёсывать список на каждый вызов RestrictClientHasRestrict() нельзя, её
    // зовут с SDKHook_Touch, то есть каждый тик на каждого игрока в триггере.
    bool Temporary;

    void Clear()
    {
        this.Count = 0;
        this.TotalDuration = 0;
        this.Admin = 0;
        this.Duration = 0;
        this.Expires = 0;
        this.Temporary = false;
    }
}

Restrict Restricts[MAXPLAYERS + 1];

// Временные рестрикты - до ближайшей смены карты. Живут только в памяти и в базу
// не попадают, поэтому работают и тогда, когда база недоступна: обычные рестрикты
// в этом случае выключены целиком (fail-open), и восстановить порядок было бы
// нечем. Ключ - аккаунт, а не слот, так что перезаход игрока рестрикт не снимает.
// Сам список читается только при подключении, выдаче и снятии; горячий путь
// смотрит в Restricts[].Temporary.
#define MAX_TEMP_RESTRICTS 64

int TempRestricts[MAX_TEMP_RESTRICTS];
int TempRestricts_Count;

void RestrictInit()
{
    RegConsoleCmd("sm_status", Command_Status);

    RegAdminCmd("sm_eban",      Command_Ban,       ADMFLAG_GENERIC);
    RegAdminCmd("sm_uneban",    Command_UnBan,     ADMFLAG_GENERIC);
    RegAdminCmd("sm_addeban",   Command_AddBan,    ADMFLAG_RCON);
    RegAdminCmd("sm_deleban",   Command_DeleteBan, ADMFLAG_RCON);
}

public Action Command_Status(int client, int args)
{
	int target = client;
	
	char buffer[64];
	if(args)
	{
		GetCmdArg(1, buffer, sizeof(buffer));
		target = FindTarget(client, buffer, true, false);
		
		if(target <= 0)
		{
			target = client;
			return Plugin_Handled;
		}
		else if(target != client)
		{
			Format(buffer, 64, " (%N)", target);
		}
		else
		{
			buffer[0] = 0;
		}
	}
	if(Clients[target].Authorized)
	{
		if(RestrictClientHasRestrict(target))
		{
			char buffer2[256];
			SetGlobalTransTarget(client);

			// У временного рестрикта нет ни срока, ни строки в базе, поэтому
			// длительность для него пишется отдельно.
			if(Restricts[target].Temporary)
			{
				FormatEx(buffer2, sizeof(buffer2), "%t", "Temporary");
			}
			else
			{
				int duration = Restricts[target].Expires != -1 ? ((Restricts[target].Expires - GetTime()) / 60):-1;
				RestrictFormatDuration(buffer2, sizeof(buffer2), duration, true);
			}

			PrintToChat2(client, "%t%s", "You have restrict", buffer2, buffer);
		}
		else
		{
			PrintToChat2(client, "%t%s", "You have not restrict", buffer);
		}
	}
	else
	{
		PrintToChat2(client, "%t%s", "You were not logged in to the database", buffer);
	}
	
	return Plugin_Handled;
}

public Action Command_Ban(int client, int args)
{
	if(args != 1 && args != 2)
	{
		ReplyToCommand(client, "%t %t!\nSyntax: sm_eban <#name|#userid> [minutes]", "Tag", "Incorrect usage");
	}
	else
	{
		char buffer[64];
		GetCmdArg(1, buffer, sizeof(buffer));

		int target = FindTarget(client, buffer, true, true);

		if(target > 0)
		{
			// Без второго аргумента - временный рестрикт, до смены карты.
			if(args == 1)
			{
				RestrictClientTempBan(target, client);
			}
			else
			{
				GetCmdArg(2, buffer, sizeof(buffer));
				RestrictClientBan(target, client, StringToInt(buffer));
			}
		}
	}
	
	return Plugin_Handled;
}

public Action Command_UnBan(int client, int args)
{
	if(args != 1)
	{
		ReplyToCommand(client, "%t %t!\nSyntax: sm_uneban <#name|#userid>", "Tag", "Incorrect usage");
	}
	else
	{
		char buffer[64];
		GetCmdArg(1, buffer, sizeof(buffer));
		
		int target = FindTarget(client, buffer, true, false);
		
		if(target > 0)
		{
			RestrictClientUnBan(target, client);
		}
	}
	
	return Plugin_Handled;
}

public Action Command_AddBan(int client, int args)
{
    if(args < 2)
    {
    	ReplyToCommand(client, "%t %t!\nSyntax: sm_addeban <minutes> [steamid] [ip]", "Tag", "Incorrect usage");
    }
    else
    {
    	char buffer[64];
        char ip[16];
    	GetCmdArg(1, buffer, sizeof(buffer));
    	int duration = StringToInt(buffer);
    	GetCmdArg(2, buffer, sizeof(buffer));
    	GetCmdArg(3, ip, sizeof(ip));
    	RestrictAddBan(duration, buffer, ip, client);
    }
    return Plugin_Handled;
}


public Action Command_DeleteBan(int client, int args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "%t %t!\nSyntax: sm_deleban [steamid] [ip]", "Tag", "Incorrect usage");
	}
	else
	{
		char steamid[64], ip[16];
		GetCmdArg(1, steamid, sizeof(steamid));
		GetCmdArg(2, ip, sizeof(ip));
		RestrictDeleteBan(steamid, ip, client);
	}
	return Plugin_Handled;
}

void RestrictCacheClientBan(int client, DBResultSet results)
{
	Restricts[client].Admin = results.FetchInt(3);
	Restricts[client].Duration = results.FetchInt(5);
	Restricts[client].Expires = results.FetchInt(6);
}

void RestrictLoadClientSummBans(int client)
{
	char ip[16];

	if(!GetClientIP(client, ip, sizeof(ip)))
        return;

	DB_Query(SQL_Callback_SelectSummBans, GetClientUserId(client), DBPrio_Normal, SELECT_SUMM_BANS, Clients[client].Account, ip);
}

public void SQL_Callback_SelectSummBans(Database db, DBResultSet results, const char[] error, int userid)
{
    // Проверяем results, а не строку ошибки: она может остаться пустой
    // при неудаче (dbi.inc:334-337), и FetchRow() ушёл бы в null.
    if(results == null)
    {
        LogError("SQL_Callback_SelectSummBans() : %s", error);
    	return;
    }

    int client = GetClientOfUserId(userid);

    if(client == 0)
        return;

    if(results.FetchRow())
    {
    	Restricts[client].Count = results.FetchInt(0);
    	Restricts[client].TotalDuration = results.FetchInt(1);
    }

    RestrictSendInfoToAdmins(client);
}

void RestrictSendInfoToAdmins(int client)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !(GetUserFlagBits(i) & (ADMFLAG_BAN | ADMFLAG_ROOT)))
			continue;
			
		if(Restricts[client].Count)
		{
			PrintToChat2(i, "%t", "Client has auth with bans", client, Restricts[client].Count, (Restricts[client].TotalDuration / 60));
		}
		else
		{
			PrintToChat2(i, "%t", "Client has auth", client);
		}
	}
}

void RestrictOnClientDisconnect(int client)
{
    Restricts[client].Clear();
}

bool LastQueryEBanNotCompleted;

void RestrictClientBan(int client, int admin, int duration)
{
    if(DB == null)
    {
    	PrintToChat2(admin, "%t", "DataBase is not loaded");
    	return;
    }
    if(!Clients[client].Authorized)
    {
    	PrintToChat2(admin, "%t", "Player is not loaded");
    	return;
    }
    if(RestrictClientHasRestrict(client))
    {
    	PrintToChat2(admin, "%t", "Player is restricted");
    	return;
    }
    if(!RestrictIsValidDuration(duration))
    {
    	PrintToChat2(admin, "%t", "Invalid duration");
    	return;
    }
    if(LastQueryEBanNotCompleted)
    {
    	PrintToChat2(admin, "%t", "The last request has not been completed yet");
    	return;
    }

    LastQueryEBanNotCompleted = true;

    int time = GetTime();
    int expires = RestrictGetExpireValue(time, duration);
        
    char ip[16];
    char names[2][64];
    char namesDb[2][MAX_NAME_LENGTH * 2 + 1];

    GetClientIP(client, ip, sizeof(ip));
    GetClientName(admin, names[0], sizeof(names[]));
    GetClientName(client, names[1], sizeof(names[]));

    DB.Escape(names[0], namesDb[0], sizeof(namesDb[]));
    DB.Escape(names[1], namesDb[1], sizeof(namesDb[]));
        
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(admin);
    pack.WriteCell(ClientGetUserId(admin));
    pack.WriteCell(duration);
    pack.WriteCell(expires);
    pack.WriteCell(Clients[admin].Account);
    pack.WriteString(names[0]);
    pack.WriteString(names[1]);

    // names[0]/namesDb[0] - имя админа, names[1]/namesDb[1] - имя игрока.
    // В таблице pname - игрок, aname - админ, поэтому порядок здесь обратный.
    DB_Query(SQL_Callback_BanClient, pack, DBPrio_High, INSERT_BAN,
             Clients[client].Account, namesDb[1], ip,
             Clients[admin].Account, namesDb[0],
             duration * 60, expires);
}

// Временный рестрикт, до ближайшей смены карты. Гейта по базе здесь нет
// намеренно: этот рестрикт для того и заведён, чтобы оставаться рабочим, когда
// базы нет. По той же причине он не занимает LastQueryEBanNotCompleted -
// запросов не будет.
void RestrictClientTempBan(int client, int admin)
{
    // 0 в этом коде значит "аккаунт неизвестен", а не ключ поиска: попади он в
    // список, под рестрикт разом попали бы все игроки без аккаунта.
    if(!Clients[client].Account)
    {
    	PrintToChat2(admin, "%t", "Player is not loaded");
    	return;
    }
    if(RestrictClientHasRestrict(client))
    {
    	PrintToChat2(admin, "%t", "Player is restricted");
    	return;
    }
    if(!RestrictAddTempRestrict(Clients[client].Account))
    {
    	PrintToChat2(admin, "%t", "Temp restrict list is full");
    	LogError("RestrictClientTempBan() : temp restrict list is full (%i entries)", MAX_TEMP_RESTRICTS);
    	return;
    }

    Restricts[client].Temporary = true;

    char names[2][64];

    GetClientName(admin, names[0], sizeof(names[]));
    GetClientName(client, names[1], sizeof(names[]));

    PrintToChatAll2("%t", "Temp ban success", names[0], names[1]);
    LogMessage("Temp ban success (Admin: %s, Target: %s)", names[0], names[1]);
}

public void SQL_Callback_BanClient(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    pack.Reset();
    char names[2][64];
    int client = GetClientOfUserId(pack.ReadCell());
    int console = pack.ReadCell();
    int admin = GetClientOfUserId(pack.ReadCell());
    int duration = pack.ReadCell();
    int expires = pack.ReadCell();
    int adminid = pack.ReadCell();
    	
    pack.ReadString(names[0], sizeof(names[]));
    pack.ReadString(names[1], sizeof(names[]));
    delete pack;
    char buffer[256];

    if(error[0])
    {
    	LastQueryEBanNotCompleted = false;
    	if(!console || (admin && IsClientInGame(admin)))
    	{
    		PrintToChat2(admin, "%t", "Query failed");
    	}
    	RestrictFormatDuration(buffer, 256, duration, false);
    	LogMessage("EBan failed (Admin: %s, Target: %s, Duration: %s)", names[0], names[1], buffer);
    	LogError("SQL_Callback_EbanClient: %s", error);
    	return;
    }
        
    if(client != 0 && IsClientInGame(client))
    {
    	Restricts[client].Admin = adminid;
    	Restricts[client].Duration = duration * 60;
    	Restricts[client].Expires = expires;
    }
        
    RestrictFormatDuration(buffer, 256, duration, true);
    PrintToChatAll2("%t", "Ban success", names[0], names[1], buffer);
    RestrictFormatDuration(buffer, 256, duration, false);
    LogMessage("Ban success (Admin: %s, Target: %s, Duration: %s)", names[0], names[1], buffer);
        
        
    if(!console)
    {
    	PrintToChat2(console, "%t", "Ban success", names[0], names[1], buffer);
    }
        
    LastQueryEBanNotCompleted = false;
}

void RestrictClientUnBan(int client, int admin)
{
    // Временный рестрикт снимается здесь и на этом команда заканчивается: в базу
    // за ним идти незачем, иначе при недоступной базе снять его было бы нечем.
    // Прав на него не спрашиваем - выдавший админ нигде не записан. Если у игрока
    // есть ещё и рестрикт из базы, админ вводит команду второй раз.
    if(Restricts[client].Temporary)
    {
    	RestrictRemoveTempRestrict(Clients[client].Account);
    	Restricts[client].Temporary = false;

    	char names[2][64];

    	GetClientName(admin, names[0], sizeof(names[]));
    	GetClientName(client, names[1], sizeof(names[]));

    	PrintToChatAll2("%t", "Temp unban success", names[0], names[1]);
    	LogMessage("Temp unban success (Admin: %s, Target: %s)", names[0], names[1]);

    	// Оба рестрикта разом sm_eban выдать не даёт, но sm_addeban выдаёт: он
    	// смотрит только в базу. Тогда игрок остаётся ограничен, и объявить
    	// "рестрикт снят" было бы неправдой - говорим админу повторить команду.
    	if(RestrictClientHasDatabaseRestrict(client))
    	{
    	    PrintToChat2(admin, "%t", "Database restrict remains");
    	}

    	return;
    }

    if(DB == null)
    {
    	PrintToChat2(admin, "%t", "DataBase is not loaded");
    	return;
    }
    if(!Clients[client].Authorized)
    {
    	PrintToChat2(admin, "%t", "Player is not loaded");
    	return;
    }
    if(!RestrictClientHasRestrict(client))
    {
    	PrintToChat2(admin, "%t", "Player is not banned");
    	return;
    }
    if(admin && Restricts[client].Admin != Clients[admin].Account && !(GetUserFlagBits(admin) & (ADMFLAG_RCON | ADMFLAG_ROOT)))
    {
    	PrintToChat2(admin, "%t", "Query denied");
    	return;
    }
    if(LastQueryEBanNotCompleted)
    {
    	PrintToChat2(admin, "%t", "The last request has not been completed yet");
    	return;
    }
    LastQueryEBanNotCompleted = true;

    char ip[16];
    char names[2][64];

    GetClientIP(client, ip, sizeof(ip));
    GetClientName(admin, names[0], sizeof(names[]));
    GetClientName(client, names[1], sizeof(names[]));

    // В пакет кладём ключ самого рестрикта, а не userid цели: снимать его из
    // памяти придётся у всех, кого затронет DELETE, а не только у неё.
    DataPack pack = new DataPack();
    pack.WriteCell(Clients[client].Account);
    pack.WriteCell(admin);
    pack.WriteCell(ClientGetUserId(admin));
    pack.WriteString(names[0]);
    pack.WriteString(names[1]);
    pack.WriteString(ip);

    DB_Query(SQL_Callback_UnBan, pack, DBPrio_Normal, DELETE_BAN, GetTime(), Clients[client].Account, ip);
}

public void SQL_Callback_UnBan(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	pack.Reset();

	char names[2][64];
	char ip[16];
	int account = pack.ReadCell();
	int console = pack.ReadCell();
	int admin = GetClientOfUserId(pack.ReadCell());
	pack.ReadString(names[0], sizeof(names[]));
	pack.ReadString(names[1], sizeof(names[]));
	pack.ReadString(ip, sizeof(ip));
	delete pack;
	if(error[0])
	{
		LastQueryEBanNotCompleted = false;
		if(!console || (admin && IsClientInGame(admin)))
		{
			PrintToChat2(admin, "%t", "Query failed");
		}
		LogMessage("UnEBan failed (Admin: %s, Target: %s)", names[0], names[1]);
		LogError("SQL_Callback_UnBan: %s", error);
		return;
	}
	
	RestrictClearCacheByBanKey(account, ip);

	PrintToChatAll2("%t", "Unban success", names[0], names[1]);
	LogMessage("Unban success (Admin: %s, Target: %s)", names[0], names[1]);
	LastQueryEBanNotCompleted = false;
}

// Снимает рестрикт из памяти у всех, кого затронул DELETE. Запрос удаляет строки
// по "pid = аккаунт ИЛИ pip = адрес", то есть освобождает и соседей по общему IP
// (за одним NAT сидят несколько игроков, и строка бана по IP относится ко всем).
// Кэш чистился только цели: сосед оставался ограничен в памяти при уже удалённой
// строке - молча, без сообщения и до самой смены карты.
void RestrictClearCacheByBanKey(int account, const char[] ip)
{
	char clientIP[16];

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || IsFakeClient(i))
			continue;

		if(!RestrictClientHasRestrict(i))
			continue;

		// account == 0 не ключ, а "аккаунт неизвестен": по нему нашлись бы все
		// неавторизованные игроки разом. Тот же принцип, что в ClientGetByAccount().
		bool affected = (account != 0 && Clients[i].Account == account);

		if(!affected && GetClientIP(i, clientIP, sizeof(clientIP)))
		{
			affected = !strcmp(clientIP, ip);
		}

		if(!affected)
			continue;

		Restricts[i].Admin = 0;
		Restricts[i].Duration = 0;
		Restricts[i].Expires = 0;
	}
}

// Минимальная проверка IPv4: только цифры и ровно три точки. Прежняя проверка
// сравнивала strlen(ip) с 16, чего буфер char[16] достичь не может, поэтому все
// ветки поиска по IP были мёртвым кодом.
bool RestrictIsValidIP(const char[] ip)
{
	int dots = 0;

	for(int i = 0; ip[i] != '\0'; i++)
	{
		if(ip[i] == '.')
		{
			dots++;
			continue;
		}

		if(!IsCharNumeric(ip[i]))
			return false;
	}

	return (dots == 3);
}

// Собирает запрос поиска действующего рестрикта. Ключом может быть SteamID, IP
// или оба сразу. IP экранируется здесь же, чтобы ни один вызывающий не мог
// подставить его в запрос сырым.
void RestrictFormatLookupQuery(char[] buffer, int maxlength, int time, int id, const char[] ip, bool ipIsValid)
{
	if(!ipIsValid)
	{
		FormatEx(buffer, maxlength, SELECT_BAN_ID, time, id);
		return;
	}

	char ipDb[16 * 2 + 1];
	DB.Escape(ip, ipDb, sizeof(ipDb));

	if(id != 0)
	{
		FormatEx(buffer, maxlength, SELECT_BAN_ID_IP, time, id, ipDb);
		return;
	}

	FormatEx(buffer, maxlength, SELECT_BAN_IP, time, ipDb);
}

// То же самое для удаления - условие обязано совпадать с условием поиска,
// иначе sm_deleban сообщит об успехе, не удалив строку.
void RestrictFormatDeleteQuery(char[] buffer, int maxlength, int time, int id, const char[] ip, bool ipIsValid)
{
	if(!ipIsValid)
	{
		FormatEx(buffer, maxlength, DELETE_BAN_ID, time, id);
		return;
	}

	char ipDb[16 * 2 + 1];
	DB.Escape(ip, ipDb, sizeof(ipDb));

	if(id != 0)
	{
		FormatEx(buffer, maxlength, DELETE_BAN_ID_IP, time, id, ipDb);
		return;
	}

	FormatEx(buffer, maxlength, DELETE_BAN_IP, time, ipDb);
}

void RestrictAddBan(int duration, const char[] steamid, const char[] ip, int admin)
{
	if(!DBLoaded)
	{
		PrintToChat2(admin, "%t", "DataBase is not loaded");
		return;
	}
	if(!RestrictIsValidDuration(duration))
	{
		PrintToChat2(admin, "%t", "Invalid duration");
		return;
	}

	int id = UTIL_GetAccountIDFromSteamID(steamid);
	bool ipIsValid = RestrictIsValidIP(ip);

	if(!id && !ipIsValid)
	{
		PrintToChat2(admin, "Invalid SteamID and IP-adress");
		return;
	}
	if(LastQueryEBanNotCompleted)
	{
		PrintToChat2(admin, "%t", "The last request has not been completed yet");
		return;
	}

	LastQueryEBanNotCompleted = true;

	int time = GetTime();
	int expires = RestrictGetExpireValue(time, duration);

	char name[64];
	GetClientName(admin, name, sizeof(name));

	DataPack pack = new DataPack();
	pack.WriteString(steamid);
	pack.WriteString(ip);
	pack.WriteString(name);

	pack.WriteCell(admin);
	pack.WriteCell(ClientGetUserId(admin));
	pack.WriteCell(id);
	pack.WriteCell(Clients[admin].Account);
	pack.WriteCell(expires);
	pack.WriteCell(duration);

	char query[256];
	RestrictFormatLookupQuery(query, sizeof(query), time, id, ip, ipIsValid);

	DB.Query(SQL_Callback_AddBanLookup, query, pack, DBPrio_Normal);
}

// Первый шаг sm_addeban: узнать, нет ли уже действующего рестрикта. Раньше этот
// поиск делался синхронным SQL_Query() под SQL_LockDatabase() - главный поток
// вставал на всё время round-trip'а, а результат утекал на нормальном пути.
public void SQL_Callback_AddBanLookup(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	pack.Reset();

	char steamid[40];
	char ip[16];
	char name[64];

	pack.ReadString(steamid, sizeof(steamid));
	pack.ReadString(ip, sizeof(ip));
	pack.ReadString(name, sizeof(name));

	int console = pack.ReadCell();
	int admin = GetClientOfUserId(pack.ReadCell());
	int id = pack.ReadCell();
	int adminId = pack.ReadCell();
	int expires = pack.ReadCell();
	int duration = pack.ReadCell();

	if(results == null)
	{
		LastQueryEBanNotCompleted = false;

		if(!console || (admin && IsClientInGame(admin)))
		{
			PrintToChat2(admin, "%t", "Query failed");
		}

		LogError("SQL_Callback_AddBanLookup: %s", error);
		delete pack;
		return;
	}

	if(results.RowCount)
	{
		LastQueryEBanNotCompleted = false;

		if(!console || (admin && IsClientInGame(admin)))
		{
			PrintToChat2(admin, "%t", "Player is restricted");
		}

		delete pack;
		return;
	}

	char nameDb[MAX_NAME_LENGTH * 2 + 1];
	char ipDb[16 * 2 + 1];

	DB.Escape(name, nameDb, sizeof(nameDb));
	DB.Escape(ip, ipDb, sizeof(ipDb));

	pack.Reset();
	DB_Query(SQL_Callback_AddBan, pack, DBPrio_Normal, INSERT_ADD_BAN, id, ipDb, adminId, nameDb, duration * 60, expires);
}


public void SQL_Callback_AddBan(Database hDatabase, DBResultSet results, const char[] error, DataPack pack)
{
    pack.Reset();
        
    char steamid[40];
    char ip[16];
    char name[64];
        
    pack.ReadString(steamid, sizeof(steamid));
    pack.ReadString(ip, sizeof(ip));
    pack.ReadString(name, sizeof(name));
        
    int console = pack.ReadCell();
    int admin = GetClientOfUserId(pack.ReadCell());
    int id = pack.ReadCell();
    int adminId = pack.ReadCell();
    int expires = pack.ReadCell();
    int duration = pack.ReadCell();
    	
    delete pack;
    char buffer[256];
    RestrictFormatDuration(buffer, 256, duration, false);
    if(error[0])
    {
    	LastQueryEBanNotCompleted = false;
    	if(!console || (admin && IsClientInGame(admin)))
    	{
    		PrintToChat2(admin, "%t", "Query failed");
    	}
    	LogMessage("AddEBan failed (Admin: %s, Target id: %s, ip = %s, duration = %s)", name, steamid, ip, buffer);
    	LogError("SQL_Callback_AddBan: %s", error);
    	return;
    }
        
    int client = ClientGetByAccount(id);
    if(client > 0)
    {
    	Restricts[client].Admin = adminId;
    	Restricts[client].Duration = duration * 60;
    	Restricts[client].Expires = expires;
    }
    LogMessage("Addban success (Admin: %s, Target id: %s, ip: %s, duration = %s)", name, steamid, ip, buffer);
    if(!console || (admin && IsClientInGame(admin)))
    {
    	RestrictFormatDuration(buffer, 256, duration, true);
    	PrintToChat2(admin, "%t", "Add ban success", steamid, ip, buffer);
    }
    LastQueryEBanNotCompleted = false;
}

void RestrictDeleteBan(const char[] steamid, const char[] ip, int admin)
{
	if(!DBLoaded)
	{
		PrintToChat2(admin, "%t", "DataBase is not loaded");
		return;
	}

	int id = UTIL_GetAccountIDFromSteamID(steamid);
	bool ipIsValid = RestrictIsValidIP(ip);

	if(!id && !ipIsValid)
	{
		PrintToChat2(admin, "Invalid SteamID and IP-adress");
		return;
	}
	if(LastQueryEBanNotCompleted)
	{
		PrintToChat2(admin, "%t", "The last request has not been completed yet");
		return;
	}

	LastQueryEBanNotCompleted = true;

	int time = GetTime();

	char name[64];
	GetClientName(admin, name, sizeof(name));

	DataPack pack = new DataPack();
	pack.WriteString(steamid);
	pack.WriteString(ip);
	pack.WriteString(name);

	pack.WriteCell(admin);
	pack.WriteCell(ClientGetUserId(admin));
	pack.WriteCell(id);
	pack.WriteCell(time);
	pack.WriteCell(ipIsValid);

	char query[256];
	RestrictFormatLookupQuery(query, sizeof(query), time, id, ip, ipIsValid);

	DB.Query(SQL_Callback_DeleteBanLookup, query, pack, DBPrio_Normal);
}

// Первый шаг sm_deleban: убедиться, что удалять есть что. Момент времени берём
// из пакета, а не заново - иначе рестрикт может истечь между поиском и
// удалением, и админ получит "успех" на нулевом количестве удалённых строк.
public void SQL_Callback_DeleteBanLookup(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	pack.Reset();

	char steamid[40];
	char ip[16];
	char name[64];

	pack.ReadString(steamid, sizeof(steamid));
	pack.ReadString(ip, sizeof(ip));
	pack.ReadString(name, sizeof(name));

	int console = pack.ReadCell();
	int admin = GetClientOfUserId(pack.ReadCell());
	int id = pack.ReadCell();
	int time = pack.ReadCell();
	bool ipIsValid = pack.ReadCell();

	if(results == null)
	{
		LastQueryEBanNotCompleted = false;

		if(!console || (admin && IsClientInGame(admin)))
		{
			PrintToChat2(admin, "%t", "Query failed");
		}

		LogError("SQL_Callback_DeleteBanLookup: %s", error);
		delete pack;
		return;
	}

	if(!results.RowCount)
	{
		LastQueryEBanNotCompleted = false;

		if(!console || (admin && IsClientInGame(admin)))
		{
			PrintToChat2(admin, "%t", "Player is not banned");
		}

		delete pack;
		return;
	}

	char query[256];
	RestrictFormatDeleteQuery(query, sizeof(query), time, id, ip, ipIsValid);

	pack.Reset();
	DB.Query(SQL_Callback_DeleteBanClient, query, pack);
}


public void SQL_Callback_DeleteBanClient(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    pack.Reset();

    char steamid[40];
    char ip[16];
    char name[64];

    pack.ReadString(steamid, sizeof(steamid));
    pack.ReadString(ip, sizeof(ip));
    pack.ReadString(name, sizeof(name));
        
    int console = pack.ReadCell();
    int admin = GetClientOfUserId(pack.ReadCell());
    int id = pack.ReadCell();
    	
    delete pack;
    if(error[0])
    {
    	LastQueryEBanNotCompleted = false;
    	if(!console || (admin && IsClientInGame(admin)))
    	{
    		PrintToChat2(admin, "%t", "Query failed");
    	}
    	LogMessage("DelEBan failed (Admin: %s, Target id: %s, ip = %s)", name, steamid, ip);
    	LogError("SQL_Callback_DeleteBanClient: %s", error);
    	return;
    }
        
    int client = ClientGetByAccount(id);
    if(client > 0)
    {
    	Restricts[client].Admin = 0;
    	Restricts[client].Duration = 0;
    	Restricts[client].Expires = 0;
    }
    LogMessage("Delete ban success (Admin: %s, Target id: %s, ip: %s)", name, steamid, ip);
    if(!console || (admin && IsClientInGame(admin)))
    {
    	PrintToChat2(admin, "%t", "Delete ban success", steamid, ip);
    }
    LastQueryEBanNotCompleted = false;
}

bool RestrictClientHasRestrict(int client)
{
	// Временный рестрикт проверяется до гейта по базе намеренно: он от неё не
	// зависит и обязан работать, когда её нет.
	if(Restricts[client].Temporary)
		return true;

	return RestrictClientHasDatabaseRestrict(client);
}

// Рестрикт из базы, без учёта временного. Нужен там, где эти два вида надо
// различать: у одного есть строка в базе и выдавший его админ, у другого нет
// ни того, ни другого.
bool RestrictClientHasDatabaseRestrict(int client)
{
	return (DBLoaded && (Restricts[client].Expires == -1 || Restricts[client].Expires > GetTime()));
}

// Пересевает кэш из списка. Зовётся из ClientAuth, как только становится известен
// аккаунт: это единственный момент, когда игрок мог получить временный рестрикт
// до своего подключения - выдали, он вышел и вернулся.
void RestrictClientInitTemp(int client)
{
	Restricts[client].Temporary = RestrictHasTempRestrict(Clients[client].Account);
}

// Сброс привязан к концу карты, а не к началу, намеренно. Кнопка Reload в
// sm_eadmin вызывает OnMapStart() руками, чтобы перечитать конфиги предметов, и
// на старте здесь она стирала бы заодно все временные рестрикты - молча, посреди
// карты. OnMapEnd она не вызывает, а настоящая смена карты вызывает всегда.
void RestrictOnMapEnd()
{
	TempRestricts_Count = 0;

	// Список опустел - опустошаем и кэш. На смене карты OnClientDisconnect
	// приходит на всех, и Clear() сбросил бы флаги сам, но полагаться на порядок
	// этих двух событий не нужно: здесь дешевле пройти по слотам явно.
	for(int i = 1; i <= MaxClients; i++)
	{
		Restricts[i].Temporary = false;
	}
}

int RestrictFindTempRestrict(int account)
{
	for(int i = 0; i < TempRestricts_Count; i++)
	{
		if(TempRestricts[i] == account)
			return i;
	}

	return -1;
}

bool RestrictHasTempRestrict(int account)
{
	return (RestrictFindTempRestrict(account) != -1);
}

// false - список переполнен. Молча терять рестрикт нельзя, поэтому решение
// принимает вызывающий: он и сообщает админу, и пишет в лог.
bool RestrictAddTempRestrict(int account)
{
	if(TempRestricts_Count >= MAX_TEMP_RESTRICTS)
		return false;

	TempRestricts[TempRestricts_Count] = account;
	TempRestricts_Count++;

	return true;
}

void RestrictRemoveTempRestrict(int account)
{
	int index = RestrictFindTempRestrict(account);

	if(index == -1)
		return;

	// Порядок в списке не значим, поэтому дырку затыкаем последним элементом,
	// а не сдвигаем хвост.
	TempRestricts_Count--;
	TempRestricts[index] = TempRestricts[TempRestricts_Count];
}

bool RestrictIsValidDuration(int duration)
{
	return (duration == -1 || 0 < duration < 525600);
}

int RestrictGetExpireValue(int time, int duration)
{
	return duration != -1 ? (time + duration * 60):-1;
}

void RestrictFormatDuration(char[] buffer, int size, int duration, bool translate)
{
    if(duration == -1)
    {
    	FormatEx(buffer, size, translate ? "%t":"%s", "Permanently");
        return;
    }

    if(translate)
    {
    	FormatEx(buffer, size, "%t", "Minutes", duration);
    }
    else
    {
    	FormatEx(buffer, size, "%i minutes", duration);
    }
}
