#define SELECT_BANS "SELECT * FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND (`pid` = %i OR `pip` = '%s') LIMIT 1;"

enum struct Client
{
    int Account;
    char SteamID[40];
    bool Authorized;

    void Clear()
    {
        this.Account = 0;
        this.SteamID[0] = 0;
        this.Authorized = false;
    }
}

Client Clients[MAXPLAYERS + 1];

public void OnClientPutInServer(int client)
{
    if(IsFakeClient(client))
        return;
        
    #if defined ADMIN_MENU
    AdminOnClientPutInServer(client);
    #endif

    GetClientAuthId(client, AuthId_Steam2, Clients[client].SteamID, sizeof(Clients[].SteamID), true);

    HudOnClientPutInServer(client);

    SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponPickup);
    SDKHook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
    SDKHook(client, SDKHook_WeaponCanUse, OnWeaponTouch);

    ClientAuth(client);
}

void ClientAuth(int client)
{
    if(DB == null)
        return;

    char ip[16];
    Clients[client].Account = GetSteamAccountID(client);
    
    if(!Clients[client].Account || !GetClientIP(client, ip, sizeof(ip)))
        return;

    DB_Query(SQL_Callback_SelectBans, GetClientUserId(client), DBPrio_Normal, SELECT_BANS, GetTime(), Clients[client].Account, ip);
}

public void SQL_Callback_SelectBans(Database db, DBResultSet results, const char[] error, int userid)
{
    if(error[0])
    {
        LogError("SQL_Callback_SelectBans() : %s", error);
    	return;
    }

    int client = GetClientOfUserId(userid);

    if(client == 0)
        return;

    if(results.FetchRow())
    {
        RestrictCacheClientBan(client, results);
    }

    RestrictLoadClientSummBans(client);

    Clients[client].Authorized = true;
    APIOnClientLoaded(client);
}

public void OnClientCookiesCached(int client)
{
    HudOnClientCookiesCached(client);
}

public void OnClientDisconnect(int client)
{
    HudOnClientDisconnect(client);

    #if defined ASSIST_USE
    AssistUseOnClientDisconnect(client);
    #endif

    Clients[client].Clear();

    RestrictOnClientDisconnect(client);
}


void ClientLostHandleAction(int client, int action)
{
    int item = -1;

    while((item = ItemFindClientItem(client, item)) != -1)
    {
        PrintToChatItemAction(item, action);
        ItemDrop(item);
    }
}

public Action OnClientSayCommand(int client, const char[] command, const char[] args)
{
    if(client == 0)
        return Plugin_Continue;

    if(IsFakeClient(client))
        return Plugin_Continue;

    #if defined ADMIN_MENU
    if(AdminOnClientSayCommand(client, args))
        return Plugin_Handled;
    #endif

    return Plugin_Continue;
}

stock int ClientGetByAccount(int account)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(Clients[i].Account == account)
		{
			return i;
		}
	}
	
	return 0;
}