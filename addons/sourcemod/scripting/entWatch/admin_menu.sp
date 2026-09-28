#if !defined ADMIN_MENU
	#endinput
#endif

#include "admin_menu/transfer.sp"
#include "admin_menu/use.sp"
#include "admin_menu/config_editor.sp"

void AdminMenuInit()
{
	RegAdminCmd("sm_eadmin", Command_Admin, ADMFLAG_GENERIC);
	AdminConfigEditorInit();
}

public Action Command_Admin(int client, int args)
{
	// Меню серверной консоли не показать, а GetUserFlagBits() и Menu.Display()
	// на нулевом индексе - ошибка натива.
	if(client == 0)
	{
		ReplyToCommand(client, "%t %t", "Tag", "Command is in-game only");
		return Plugin_Handled;
	}

	AdminMenu(client);
	return Plugin_Handled;
}

void AdminMenu(int client)
{
	int flags = GetUserFlagBits(client);
	SetGlobalTransTarget(client);

	Menu menu = new Menu(AdminMenu_Handler, MenuAction_End | MenuAction_Select);
	menu.SetTitle("%t", "Admin title");
	
	#if defined RESTRICT_BUILTIN
	if(flags & (ADMFLAG_BAN | ADMFLAG_RCON | ADMFLAG_ROOT))
	{
		AddMenuItem2(menu, _, "eban", "%t", "Ban item");
		AddMenuItem2(menu, _, "vieweban", "%t", "Banned players item");
	}
	#endif
	AddMenuItem2(menu, _, "transfer", "%t", "Transfer item");
	#if defined ASSIST_USE
	if(flags & (ADMFLAG_BAN | ADMFLAG_RCON | ADMFLAG_ROOT))
	{
		AddMenuItem2(menu, _, "use", "%t", "Use item");
	}
	#endif
	if(flags & (ADMFLAG_RCON | ADMFLAG_ROOT))
	{
		AddMenuItem2(menu, _, "configs", "%t", "Configs item");
		AddMenuItem2(menu, _, "save", "%t", "Save item");
		AddMenuItem2(menu, _, "reload", "%t", "Reload item");
	}

	menu.Display(client, 0);
}

public int AdminMenu_Handler(Menu menu, MenuAction action, int client, int index)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Select:
		{
			char buffer[4];
			menu.GetItem(index, buffer, 4);
			switch(buffer[0])
			{
				#if defined RESTRICT_BUILTIN
				case 'e':
				{
					BanMenu(client);
				}
				case 'v':
				{
					BannedPlayersMenu(client);
				}
				#endif
				case 't':
				{
					TransferMenu(client);
				}

				#if defined ASSIST_USE
				case 'u':
				{
					UseItemsMenu(client);
				}
				#endif

				case 'c':
				{
					ConfigsMenu(client);
				}
				case 's':
				{
					AdminConfigSave();
					AdminMenu(client);
				}
				case 'r':
				{
					// RoundStarted нужно вернуть в то состояние, в котором была
					// перезагрузка. OnMapStart() под Late уходит в полное
					// сканирование и выставляет его в true; если админ нажал
					// Reload между раундами, подсистема остаётся вооружённой,
					// сущности следующего раунда регистрируются здесь (хук №1),
					// а round_start вешает второй - ItemsClear() снимает учёт,
					// но не хуки. Весь следующий раунд одно нажатие считалось
					// бы за два.
					bool roundStarted = RoundStarted;

					Late = true;
					OnPluginEnd();
					OnRoundEnd(null, "", false);
					OnMapStart();
					Late = false;

					RoundStarted = roundStarted;

					AdminMenu(client);
				}
			}
		}
	}

	return 0;
}

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

void AddMenuItem2(Menu menu, int flags = ITEMDRAW_DEFAULT, const char[] desc = "", const char[] title, any ...)
{
	int iLen = strlen(title) + 255;
	char[] buffer = new char[iLen];
	VFormat(buffer, iLen, title, 5);
	
	menu.AddItem(desc, buffer, flags);
}