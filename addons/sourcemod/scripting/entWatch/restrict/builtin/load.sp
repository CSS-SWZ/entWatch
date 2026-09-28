#define SELECT_BANS "SELECT * FROM `ebans` WHERE (`expires` = -1 OR `expires` > %i) AND (`pid` = %i OR `pip` = '%s') LIMIT 1;"

void RestrictOnClientAuth(int client)
{
    // Аккаунт стал известен - только теперь можно узнать, висит ли на игроке
    // временный рестрикт, выданный до его переподключения.
    RestrictClientInitTemp(client);

    // Гейт именно по DBLoaded, а не по "DB != null": на пути SQLite соединение
    // готово сразу, а таблиц ещё нет - запрос из OnPluginStart уходил впустую,
    // после чего SQL_Callback_CreateTables() авторизовал того же игрока второй
    // раз, и entWatch_OnClientLoaded улетал дважды.
    if(!DBLoaded)
    {
        // Базы нет - значит нет и рестриктов: тот же fail-open, что и в
        // RestrictClientHasRestrict(), иначе игрок не сможет поднять предмет.
        // Форвард отсюда не шлём - загрузка ещё не состоялась, её выполнит
        // повторный вызов из SQL_Callback_CreateTables().
        Clients[client].Authorized = true;
        return;
    }

    char ip[16];

    if(!Clients[client].Account || !GetClientIP(client, ip, sizeof(ip)))
        return;

    DB_Query(SQL_Callback_SelectBans, GetClientUserId(client), DBPrio_Normal, SELECT_BANS, GetTime(), Clients[client].Account, ip);
}

public void SQL_Callback_SelectBans(Database db, DBResultSet results, const char[] error, int userid)
{
    int client = GetClientOfUserId(userid);

    if(client == 0)
        return;

    // Проверяем именно results: строка ошибки может остаться пустой при неудаче (dbi.inc:334-337).
    if(results == null)
    {
        // Ответа от БД нет - значит и рестрикта нет. Тот же fail-open,
        // что и в RestrictClientHasRestrict(), иначе игрок навсегда останется
        // без права поднимать предметы (OnWeaponTouch).
        LogError("SQL_Callback_SelectBans() : %s", error);
    }
    else
    {
        if(results.FetchRow())
        {
            RestrictCacheClientBan(client, results);
        }

        RestrictLoadClientSummBans(client);
    }

    Clients[client].Authorized = true;
    APIOnClientLoaded(client);
}

#define SELECT_SUMM_BANS    "SELECT COUNT(`pid`), SUM(`duration`) FROM `ebans` WHERE (`pid` = %i OR `pip` = '%s');"
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

