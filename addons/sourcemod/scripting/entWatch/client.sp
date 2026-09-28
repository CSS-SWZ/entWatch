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

void ClientsOnClientPutInServer(int client)
{
    GetClientAuthId(client, AuthId_Steam2, Clients[client].SteamID, sizeof(Clients[].SteamID), true);

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

void ClientsOnClientDisconnect(int client)
{
    Clients[client].Clear();
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
stock int ClientGetUserId(int client)
{
	if(client == 0)
	{
		return 0;
	}

	return GetClientUserId(client);
}