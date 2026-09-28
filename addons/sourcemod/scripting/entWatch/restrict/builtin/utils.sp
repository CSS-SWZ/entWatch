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
// R1KO
stock int UTIL_GetAccountIDFromSteamID(const char[] steamid)
{
	if (!strncmp(steamid, "STEAM_", 6))
	{
		// Формат STEAM_X:Y:Z. Без проверки длины индексы 8 и 10 читают за
		// терминатором: обрезанный "STEAM_" давал id = -48, который проходил
		// проверку "id != 0" и уходил в базу как чужой аккаунт.
		if (strlen(steamid) < 11)
			return 0;

		if (steamid[8] != '0' && steamid[8] != '1')
			return 0;

		return StringToInt(steamid[10]) << 1 | (steamid[8] - 48);
	}

	if (!strncmp(steamid, "[U:1:", 5) && steamid[strlen(steamid)-1] == ']')
	{
		char buffer[16];
		strcopy(buffer, sizeof(buffer), steamid[5]);
		buffer[strlen(buffer)-1] = 0;

		return StringToInt(buffer);
	}

	return 0;
}

stock void UTIL_GetSteamIDFromAccountID(int account, char[] steamid, int maxlen)
{
	FormatEx(steamid, maxlen, "[U:1:%u]", account);
}

