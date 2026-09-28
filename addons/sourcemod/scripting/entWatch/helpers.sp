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