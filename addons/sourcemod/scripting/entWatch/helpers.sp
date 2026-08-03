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

stock void RemoveConfig(int config)
{
	for(int i = config; i < Configs_Count - 1; i++)
	{
		Configs[i] = Configs[i + 1];
	}

	Configs_Count--;

	RemoveItemByConfig(config);
}

stock void RemoveItemByConfig(int config)
{
	int i = 0;

	while(i < Items_Count)
	{
		if(Items[i].Config == config)
		{
			// Слот нужно освободить целиком: снять хуки с ещё живых кнопки,
			// триггера, compare и relay, иначе они продолжат срабатывать на
			// предмет, которого больше нет.
			ItemUnhook(i);
			ItemClear(i);
			ItemRemove(i);

			// ItemRemove() сдвинул массив вниз - на этом же индексе теперь
			// стоит следующий предмет, поэтому i не увеличиваем.
			continue;
		}

		if(Items[i].Config > config)
		{
			Items[i].Config--;
		}

		i++;
	}
}

bool AreEntitiesRelated(int child, int owner)
{
	int parent = GetEntPropEnt(child, Prop_Data, "m_pParent");
	
	if(parent == INVALID_ENT_REFERENCE)
		return false;
	
	if(parent == owner)
		return true;
		
	return AreEntitiesRelated(parent, owner);
}

// Sg
stock void StringToLowercase(char[] text)
{
	int length = strlen(text);
	for(int i = 0; i < length; ++i)
	{
		if(IsCharUpper(text[i]))
		{
			text[i] = CharToLower(text[i]);
		}
	}
}