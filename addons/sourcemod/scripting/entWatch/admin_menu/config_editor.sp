enum struct EditClientConfig
{
	int Slot;
	int StartIndex;
	int Config;

	void Init(int config)
	{
		this.Slot = -1;
		this.StartIndex = 0;
		this.Config = config;
	}
	void Clear()
	{
		this.Slot = -1;
		this.StartIndex = 0;
		this.Config = -1;
	}
	bool IsEdit()
	{
		return (this.Config != -1);
	}
}

EditClientConfig EditClientsConfigs[MAXPLAYERS + 1];

// Сентинел "не редактирует" - это -1, а глобальный массив стартует нулями, то
// есть слот читается как "правит конфиг #0". Слоты, не проходившие через
// AdminOnClientPutInServer() - свободные и боты, включая SourceTV, у которых
// OnClientPutInServer() выходит по IsFakeClient, - иначе держат редактор
// занятым всё время работы плагина, и AdminConfigEditorGet() отвечает "занято"
// на любое действие в меню конфигов.
void AdminConfigEditorInit()
{
	for(int i = 1; i <= MAXPLAYERS; i++)
	{
		EditClientsConfigs[i].Clear();
	}
}

// Редактор конфигов один на сервер. Два админа, правящие Configs[] одновременно,
// затирают правки друг друга, а удаление конфига сдвигает массив под чужим
// сохранённым индексом. Отдельного флага не держим: занятость выводится из
// состояния самих редакторов и потому не может с ним разойтись.
int AdminConfigEditorGet()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(EditClientsConfigs[i].IsEdit())
		{
			return i;
		}
	}

	return 0;
}

void ConfigsMenu(int client)
{
	SetGlobalTransTarget(client);

	char buffer[256];
	Menu menu = new Menu(ConfigsMenu_Handler, MenuAction_Cancel | MenuAction_End | MenuAction_Select);
	menu.SetTitle("%t", "Configs title");
	
	int count = 0;
	
	AddMenuItem2(menu, _, "Add", "%t", "Add config item");
	for(int i = 0; i < Configs_Count; i++)
	{
		IntToString(i, buffer, sizeof(buffer));
		menu.AddItem(buffer, Configs[i].ShortName[0] ? Configs[i].ShortName:Configs[i].Name[0] ? Configs[i].Name:"Unknown item");
		
		if(++count > 5 && count % 6 == 0 && i < Configs_Count)
		{
			AddMenuItem2(menu, _, "Add", "%t", "Add config item");
		}
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, 0);
}

public int ConfigsMenu_Handler(Menu menu, MenuAction action, int client, int index)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if(index == MenuCancel_ExitBack)
			{
				AdminMenu(client);
			}
		}
		case MenuAction_Select:
		{
			if(AdminConfigEditorGet() != 0)
			{
				PrintToChat2(client, "\x07%s%t", Colors[COLOR_OTHER], "Config editor is busy");
				AdminMenu(client);
				return 0;
			}

			char buffer[32];
			menu.GetItem(index, buffer, sizeof(buffer));
			
			if(!strcmp(buffer, "Add", false))
			{
				if(Configs_Count < MAX_CONFIGS)
				{
					int config = Configs_Count;
					ConfigInit(config, CONFIG_TYPE_UNLOZE);
					EditClientsConfigs[client].Init(config);
					Configs_Count++;

					ConfigMenu(client);
				}
				else
				{
					AdminMenu(client);
				}
			}
			else
			{
				EditClientsConfigs[client].Init(StringToInt(buffer));
				ConfigMenu(client);
			}
		}
	}
	
	return 0;
}

void ConfigMenu(int client)
{
	int slot = EditClientsConfigs[client].Slot;
	int cfg = EditClientsConfigs[client].Config;
	int startIndex = EditClientsConfigs[client].StartIndex;

	SetGlobalTransTarget(client);

	Menu menu = new Menu(ConfigMenu_Handler, MenuAction_Cancel | MenuAction_End | MenuAction_Select);
	menu.SetTitle("%t", "Config title");

	AddMenuItem2(menu, _, "", "[Remove item]");
	AddMenuItem2(menu, Configs[cfg].Template[0] ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "[Spawn item]");
	AddMenuItem2(menu, slot != 0 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "Name\n%s", Configs[cfg].Name);
	AddMenuItem2(menu, slot != 1 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "Short name\n%s", Configs[cfg].ShortName);
	AddMenuItem2(menu, slot != 2 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "Color\n%s", Configs[cfg].Color[1]);
	AddMenuItem2(menu, slot != 3 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "Filter\n%s", Configs[cfg].Filter);
	AddMenuItem2(menu, slot != 4 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "Weapon\n%i", Configs[cfg].Weapon_HammerId);
	AddMenuItem2(menu, slot != 5 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "Button\n%i", Configs[cfg].Button_HammerId);
	AddMenuItem2(menu, slot != 6 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "Trigger\n%i", Configs[cfg].Trigger_HammerId);
	AddMenuItem2(menu, slot != 7 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "Mode\n%i", Configs[cfg].Mode);
	AddMenuItem2(menu, slot != 8 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "Slot\n%i", Configs[cfg].Slot);
	AddMenuItem2(menu, slot != 9 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "Maxuses\n%i", Configs[cfg].Maxuses);
	AddMenuItem2(menu, slot != 10 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "Cooldown\n%.1f", Configs[cfg].Cooldown);
	AddMenuItem2(menu, slot != 11 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "Display\n%i", Configs[cfg].Display);
	AddMenuItem2(menu, slot != 12 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "Spawn\n%s", Configs[cfg].Template);
	AddMenuItem2(menu, slot != 13 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "Compare\n%i", Configs[cfg].Compare_HammerId);
	AddMenuItem2(menu, slot != 14 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED, "", "Relay\n%i", Configs[cfg].Relay_HammerId);

	menu.ExitBackButton = true;
	menu.DisplayAt(client, startIndex, 0);
}

public int ConfigMenu_Handler(Menu menu, MenuAction action, int client, int index)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			EditClientsConfigs[client].Clear();

			if(index == MenuCancel_ExitBack)
			{
				ConfigsMenu(client);
			}
		}
		case MenuAction_Select:
		{
			EditClientsConfigs[client].StartIndex = menu.Selection;
			
			switch(index)
			{
				case 0:
				{
					int config = EditClientsConfigs[client].Config;

					// Состояние редактора нужно сбросить до удаления: RemoveConfig()
					// сдвигает Configs[], и сохранённый индекс начнёт указывать
					// на соседний конфиг - следующая реплика админа ушла бы в него.
					EditClientsConfigs[client].Clear();

					RemoveConfig(config);
					ConfigsMenu(client);
				}
				case 1:
				{
					SpawnItem(EditClientsConfigs[client].Config, client, client);
					ConfigMenu(client);
				}
				default:
				{
					EditClientsConfigs[client].Slot = index - 2;
					ConfigMenu(client);
				}
			}
		}
	}
	
	return 0;
}

void AdminOnClientPutInServer(int client)
{
	EditClientsConfigs[client].Clear();
}

bool AdminOnClientSayCommand(int client, const char[] args)
{
	if(!EditClientsConfigs[client].IsEdit())
		return false;

	int cfg = EditClientsConfigs[client].Config;
	switch(EditClientsConfigs[client].Slot)
	{
		case -1:
		{
			return false;
		}
		case 0:
		{
			strcopy(Configs[cfg].Name, sizeof(Configs[].Name), args);
		}
		case 1:
		{
			strcopy(Configs[cfg].ShortName, sizeof(Configs[].ShortName), args);
		}
		case 2:
		{
			// Под текст цвета отведено на байт меньше: Color[0] занят символом '#'.
			// С полным размером strcopy() положил бы терминатор в Filter[0]
			// и стёр бы имя фильтра, на котором держится защита старых карт.
			strcopy(Configs[cfg].Color[1], sizeof(Configs[].Color) - 1, args);
		}
		case 3:
		{
			strcopy(Configs[cfg].Filter, sizeof(Configs[].Filter), args);
		}
		case 4:
		{
			Configs[cfg].Weapon_HammerId = StringToInt(args);
		}
		case 5:
		{
			Configs[cfg].Button_HammerId = StringToInt(args);
		}
		case 6:
		{
			Configs[cfg].Trigger_HammerId = StringToInt(args);
		}
		case 7:
		{
			// Тот же зажим, что и в парсерах конфига. Без него неизвестный
			// режим проваливается в default у ItemIsReady(), и предмет
			// становится вечно готовым.
			int mode = StringToInt(args);

			if(mode < MODE_PROTECT || mode > MODE_CHARGESCD)
			{
				mode = MODE_PROTECT;
			}

			Configs[cfg].Mode = mode;
		}
		case 8:
		{
			int slot = StringToInt(args);

			if(slot < SLOT_NONE || slot > SLOT_GRENADES)
			{
				slot = SLOT_DEFAULT;
			}

			Configs[cfg].Slot = slot;
		}
		case 9:
		{
			Configs[cfg].Maxuses = StringToInt(args);
		}
		case 10:
		{
			Configs[cfg].Cooldown = StringToFloat(args);
		}
		case 11:
		{
			// Display - битовая маска из трёх флагов; посторонние биты
			// ни на что не влияют, но попадают в сохранённый конфиг.
			Configs[cfg].Display = StringToInt(args) & (DISPLAY_CHAT | DISPLAY_USE | DISPLAY_HUD);
		}
		case 12:
		{
			strcopy(Configs[cfg].Template, sizeof(Configs[].Template), args);
		}
		case 13:
		{
			Configs[cfg].Compare_HammerId = StringToInt(args);
		}
		case 14:
		{
			Configs[cfg].Relay_HammerId = StringToInt(args);
		}

	}
	EditClientsConfigs[client].Slot = -1;
	EditClientConfig editItemCopy;
	editItemCopy = EditClientsConfigs[client];
	ConfigMenu(client);
	EditClientsConfigs[client] = editItemCopy;
	return true;
}

