#define INSERT_BAN          "INSERT INTO `ebans` (`pid`, `pname`, `pip`, `aid`, `aname`, `duration`, `expires`) VALUES (%i, '%s', '%s', %i, '%s', %i, %i);"
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

