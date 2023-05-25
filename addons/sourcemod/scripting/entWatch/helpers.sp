// R1KO
stock int UTIL_GetAccountIDFromSteamID(const char[] steamid)
{
	if (!strncmp(steamid, "STEAM_", 6))
	{
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
	for(int i = config; i < Configs_Count; i++)
	{
		Configs[i] = Configs[i + 1];

	}
	RemoveItemByConfig(config);
}

stock void RemoveItemByConfig(int config)
{
	for(int i = 0; i < Items_Count; i++)
	{
		if(Items[i].Config == config)
		{
			ItemClear(i);
			continue;
		}

		if(Items[i].Config > config)
		{
			Items[i].Config--;
		}

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