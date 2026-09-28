#define DELETE_BAN          "DELETE FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND (`pid` = %i OR `pip` = '%s')"
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

