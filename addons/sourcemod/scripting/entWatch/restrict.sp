#define SELECT_SUMM_BANS    "SELECT COUNT(`pid`), SUM(`duration`) FROM `ebans` WHERE (`pid` = %i OR `pip` = '%s');"
#define INSERT_BAN          "INSERT INTO `ebans` (`pid`, `pname`, `pip`, `aid`, `aname`, `duration`, `expires`) VALUES (%i, '%s', '%s', %i, '%s', %i, %i);"
#define DELETE_BAN          "DELETE FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND (`pid` = %i OR `pip` = '%s')"
#define INSERT_ADD_BAN      "INSERT INTO `ebans` (`pid`, `pip`, `aid`, `aname`, `duration`, `expires`) VALUES (%i, '%s', %i, '%s', %i, %i);"

enum struct Restrict
{
    int Count;
    int TotalDuration;

    // Current restrict
    int Admin;
    int Duration;
    int Expires;

    void Clear()
    {
        this.Count = 0;
        this.TotalDuration = 0;
        this.Admin = 0;
        this.Duration = 0;
        this.Expires = 0;
    }
}

Restrict Restricts[MAXPLAYERS + 1];

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
		GetCmdArg(1, buffer, 32);
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
			int duration = Restricts[target].Expires != -1 ? ((Restricts[target].Expires - GetTime()) / 60):-1;
			RestrictFormatDuration(buffer2, 256, duration, true);
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
	if(args != 2)
	{
		ReplyToCommand(client, "%t %t!\nSyntax: sm_eban <#name|#userid> <minutes>", "Tag", "Incorrect usage");
	}
	else
	{
		char buffer[64];
		GetCmdArg(1, buffer, sizeof(buffer));
		
		int target = FindTarget(client, buffer, true, true);
		
		if(target > 0)
		{
			GetCmdArg(2, buffer, sizeof(buffer));
			RestrictClientBan(target, client, StringToInt(buffer));
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
    if(error[0])
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
    pack.WriteCell(GetClientUserId(admin));
    pack.WriteCell(duration);
    pack.WriteCell(expires);
    pack.WriteCell(Clients[admin].Account);
    pack.WriteString(names[0]);
    pack.WriteString(names[1]);

    DB_Query(SQL_Callback_BanClient, pack, DBPrio_High, INSERT_BAN, Clients[client].Account, namesDb[0], ip, Clients[admin].Account, namesDb[1], duration * 60, expires);
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
        
    if(IsClientInGame(client))
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

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(admin);
    pack.WriteCell(GetClientUserId(admin));
    pack.WriteString(names[0]);
    pack.WriteString(names[1]);

    DB_Query(SQL_Callback_UnBan, pack, DBPrio_Normal, DELETE_BAN, GetTime(), Clients[client].Account, ip);
}

public void SQL_Callback_UnBan(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	pack.Reset();

	char names[2][64];
	int client = GetClientOfUserId(pack.ReadCell());
	int console = pack.ReadCell();
	int admin = GetClientOfUserId(pack.ReadCell());
	pack.ReadString(names[0], sizeof(names[]));
	pack.ReadString(names[1], sizeof(names[]));
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
	
	if(IsClientInGame(client))
	{
		Restricts[client].Admin = 0;
		Restricts[client].Duration = 0;
		Restricts[client].Expires = 0;
	}
	PrintToChatAll2("%t", "Unban success", names[0], names[1]);
	LogMessage("Unban success (Admin: %s, Target: %s)", names[0], names[1]);
	LastQueryEBanNotCompleted = false;
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
    bool ipIsValid = (strlen(ip) == 16);
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
    int time = GetTime(), expires = RestrictGetExpireValue(time, duration);
    char buffer[256];
        
    if(id && ipIsValid)
    {
    	FormatEx(buffer, 256, "SELECT `pid` FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND (`pid` = %i AND `pip` = '%s') LIMIT 1", time, id, ip);
    }
    else if(id)
    {
    	FormatEx(buffer, 256, "SELECT `pid` FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND `pid` = %i LIMIT 1", time, id);
    }
    else
    {
    	FormatEx(buffer, 256, "SELECT `pid` FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND `pip` = '%s' LIMIT 1", time, ip);
    }
    SQL_LockDatabase(DB);
    DBResultSet results = SQL_Query(DB, buffer);
    SQL_UnlockDatabase(DB);
        
    if(results && results.RowCount)
    {
    	if(admin)
    	{
    		PrintToChat2(admin, "%t", "Player is restricted");
    	}
    	LastQueryEBanNotCompleted = false;
        delete results;
    }
    else
    {
    	char name[64];
    	GetClientName(admin, name, sizeof(name));
    	DataPack pack = new DataPack();
    	pack.WriteString(steamid);
    	pack.WriteString(ip);
    	pack.WriteString(name);
    	
    	pack.WriteCell(admin);
    	pack.WriteCell(GetClientUserId(admin));
    	pack.WriteCell(id);
    	pack.WriteCell(Restricts[admin].Admin);
    	pack.WriteCell(expires);
    	pack.WriteCell(duration);
        

    	DB_Query(SQL_Callback_AddBan, pack, DBPrio_Normal, INSERT_ADD_BAN, id, ip, Clients[admin].Account, name, duration * 60, expires);
    }
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
	bool ipIsValid = (strlen(ip) == 16);
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
	char buffer[256];
	
	if(id && ipIsValid)
	{
		FormatEx(buffer, 256, "SELECT `pid` FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND (`pid` = %i AND `pip` = '%s') LIMIT 1", time, id, ip);
	}
	else if(id)
	{
		FormatEx(buffer, 256, "SELECT `pid` FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND `pid` = %i LIMIT 1", time, id);
	}
	else
	{
		FormatEx(buffer, 256, "SELECT `pid` FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND `pip` = '%s' LIMIT 1", time, ip);
	}
	
	SQL_LockDatabase(DB);
	DBResultSet results = SQL_Query(DB, buffer);
	SQL_UnlockDatabase(DB);
	
	if(!results || !results.RowCount)
	{
		if(admin)
		{
			PrintToChat2(admin, "%t", "Player is not banned");
		}
		LastQueryEBanNotCompleted = false;
	}
	else
	{
		char name[64];
		GetClientName(admin, name, sizeof(name));
		
		if(id && ipIsValid)
		{
			FormatEx(buffer, 256, "DELETE FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND (`pid` = %i AND `pip` = '%s')", time, id, ip);
		}
		else if(id)
		{
			FormatEx(buffer, 256, "DELETE FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND `pid` = %i", time, id);
		}
		else
		{
			FormatEx(buffer, 256, "DELETE FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND `pip` = '%s'", time, ip);
		}
		DataPack pack = new DataPack();
		pack.WriteString(steamid);
		pack.WriteString(ip);
		pack.WriteString(name);
		
		pack.WriteCell(admin);
		pack.WriteCell(GetClientUserId(admin));
		pack.WriteCell(id);
		DB.Query(SQL_Callback_DeleteBanClient, buffer, pack);
	}
}


public void SQL_Callback_DeleteBanClient(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    pack.Reset();

    char steamid[40];
    char ip[16]
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
	return (DBLoaded && (Restricts[client].Expires == -1 || Restricts[client].Expires > GetTime()));
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