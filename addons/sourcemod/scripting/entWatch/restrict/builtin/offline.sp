#define INSERT_ADD_BAN      "INSERT INTO `ebans` (`pid`, `pip`, `aid`, `aname`, `duration`, `expires`) VALUES (%i, '%s', %i, '%s', %i, %i);"

#define SELECT_BAN_ID_IP    "SELECT `pid` FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND (`pid` = %i AND `pip` = '%s') LIMIT 1;"
#define SELECT_BAN_ID       "SELECT `pid` FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND `pid` = %i LIMIT 1;"
#define SELECT_BAN_IP       "SELECT `pid` FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND `pip` = '%s' LIMIT 1;"

#define DELETE_BAN_ID_IP    "DELETE FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND (`pid` = %i AND `pip` = '%s');"
#define DELETE_BAN_ID       "DELETE FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND `pid` = %i;"
#define DELETE_BAN_IP       "DELETE FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND `pip` = '%s';"

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

