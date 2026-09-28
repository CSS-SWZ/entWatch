#if !defined ADMIN_MENU
	#endinput
#endif

void AdminConfigSave()
{
	char map[64];
	GetCurrentMap(map, sizeof(map));
	StringToLowercase(map);

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/entwatch/%s.cfg", map);

	KeyValues kv = new KeyValues("entities");

	// Основой берём текущий конфиг карты, а не пустой шаблон: иначе корневые
	// ключи (hud, assist_use) пропадут при первом же сохранении. Если файла
	// ещё нет, пишем с нуля - ключи предметов создаёт сам JumpToKey().
	if(FileExists(path) && !kv.ImportFromFile(path))
	{
		LogMessage("AdminConfigSave() : failed to read %s", path);
		delete kv;
		return;
	}

	AdminConfigBrowseItems(kv);

	kv.Rewind();
	kv.ExportToFile(path);
	delete kv;
}

void AdminConfigBrowseItems(KeyValues kv)
{
	char key[8];
	for(int i = 0; i < Configs_Count; i++)
	{
		IntToString(i, key, sizeof(key));
		
		if(!kv.JumpToKey(key, true))
	        continue;

		kv.SetString("name", Configs[i].Name);
		kv.SetString("color", Configs[i].Color[1]);
		kv.SetNum("maxuses", Configs[i].Maxuses);
		kv.SetFloat("cooldown", Configs[i].Cooldown);
		kv.SetString("spawn", Configs[i].Template);
		kv.SetNum("buttonid", Configs[i].Button_HammerId);
		kv.SetNum("triggerid", Configs[i].Trigger_HammerId);
		kv.SetNum("compareid", Configs[i].Compare_HammerId);
		kv.SetNum("relayid", Configs[i].Relay_HammerId);
		
		
		switch(Configs[i].Type)
		{
			case CONFIG_TYPE_GFL:
			{
				kv.SetString("shortname", Configs[i].ShortName);
				kv.SetString("filtername", Configs[i].Filter);
				kv.SetNum("hammerid", Configs[i].Weapon_HammerId);
				kv.SetNum("chat", ConfigGetDisplay(i, DISPLAY_CHAT) ? 1:0);
				kv.SetNum("activate", ConfigGetDisplay(i, DISPLAY_USE) ? 1:0);
				kv.SetNum("hud", ConfigGetDisplay(i, DISPLAY_HUD) ? 1:0);
		
				kv.SetNum("mode", Configs[i].Mode + 1);
		
				// Оба ключа пишем всегда. Читатель считает отсутствующий ключ
				// единицей (config.sp), поэтому ножевой предмет вернулся бы
				// после сохранения передаваемым - а ножи не передаются.
				int transferable = 0;

				if(Configs[i].Slot == SLOT_PRIMARY || Configs[i].Slot == SLOT_SECONDARY)
				{
					transferable = 1;
				}

				kv.SetNum("allowtransfer", transferable);
				kv.SetNum("forcedrop", transferable);
			}
			case CONFIG_TYPE_UNLOZE:
			{
				kv.SetNum("weaponid", Configs[i].Weapon_HammerId);
				kv.SetString("short", Configs[i].ShortName);
				kv.SetString("filter", Configs[i].Filter);
				kv.SetNum("display", Configs[i].Display);
				kv.SetNum("slot", Configs[i].Slot);
		
				kv.SetNum("mode", Configs[i].Mode);
		
			}
		}
		kv.GoBack();
	}
}

