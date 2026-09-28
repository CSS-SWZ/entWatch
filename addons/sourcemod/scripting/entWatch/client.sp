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

    #if defined HUD
    HudOnClientPutInServer(client);
    #endif

    SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponPickup);
    SDKHook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
    SDKHook(client, SDKHook_WeaponCanUse, OnWeaponTouch);

    ClientAuth(client);
}

void ClientAuth(int client)
{
    Clients[client].Account = GetSteamAccountID(client);

    RestrictOnClientAuth(client);
}

public void OnClientCookiesCached(int client)
{
    #if defined HUD
    HudOnClientCookiesCached(client);
    #endif
}

public void OnClientDisconnect(int client)
{
    #if defined HUD
    HudOnClientDisconnect(client);
    #endif
    
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

        // Ножевой предмет на землю не падает, но владельца теряет всё равно:
        // иначе труп остаётся владельцем и может использовать материю.
        if(!ItemDrop(item))
        {
            ItemReleaseOwner(item);
        }
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
	// 0 - это "аккаунт неизвестен", а не ключ поиска. Иначе найдётся первый
	// игрок, у которого Clients[].Account ещё не заполнен, и рестрикт по IP
	// (у него pid = 0) применился бы к постороннему.
	if(account == 0)
	{
		return 0;
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(Clients[i].Account == account)
		{
			return i;
		}
	}
	
	return 0;
}

// Возвращает userid игрока. Для серверной консоли (client == 0) возвращает 0:
// GetClientUserId() на нулевом индексе - ошибка натива, а не 0.
int ClientGetUserId(int client)
{
	if(client == 0)
	{
		return 0;
	}

	return GetClientUserId(client);
}