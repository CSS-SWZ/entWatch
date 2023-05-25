#if !defined ADMIN_MENU
	#endinput
#endif

void AdminMenuInit()
{
	RegAdminCmd("sm_eadmin", Command_Admin, ADMFLAG_GENERIC);
}

public Action Command_Admin(int client, int args)
{
	AdminMenu(client);
	return Plugin_Handled;
}

void AdminMenu(int client)
{
	int flags = GetUserFlagBits(client);
	SetGlobalTransTarget(client);

	Menu menu = new Menu(AdminMenu_Handler, MenuAction_End | MenuAction_Select);
	menu.SetTitle("%t", "Admin title");
	
	if(flags & (ADMFLAG_BAN | ADMFLAG_RCON | ADMFLAG_ROOT))
	{
		AddMenuItem2(menu, _, "eban", "%t", "Ban item");
		AddMenuItem2(menu, _, "vieweban", "%t", "Banned players item");
	}
	AddMenuItem2(menu, _, "transfer", "%t", "Transfer item");
	#if defined ASSIST_USE
	AddMenuItem2(menu, _, "use", "%t", "Use item");
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
				case 'e':
				{
					BanMenu(client);
				}
				case 'v':
				{
					BannedPlayersMenu(client);
				}
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
					Late = true;
					OnPluginEnd();
					OnRoundEnd(null, "", false);
					OnMapStart();
					AdminMenu(client);
					Late = false;
				}
			}
		}
	}

	return 0;
}

void BanMenu(int client)
{
	SetGlobalTransTarget(client);

	char buffer[32];
	char buffer2[16];
	
	Menu menu = new Menu(BanMenu_Handler, MenuAction_Cancel | MenuAction_End | MenuAction_Select);
	menu.SetTitle("%t", "Ban title");
	
	int count = 0;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !Clients[i].Authorized || RestrictClientHasRestrict(i))
			continue;

		GetClientName(i, buffer, sizeof(buffer))
		IntToString(GetClientUserId(i), buffer2, sizeof(buffer2));
		menu.AddItem(buffer2, buffer);
		count++;
	}
	
	if(count == 0)
	{
		AddMenuItem2(menu, ITEMDRAW_DISABLED, "", "%t", "No players");
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, 0);
}

public int BanMenu_Handler(Menu menu, MenuAction action, int client, int index)
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
			char buffer[16];
			menu.GetItem(index, buffer, sizeof(buffer));
			int target = GetClientOfUserId(StringToInt(buffer));

			if(target == 0 || !IsClientInGame(target) || RestrictClientHasRestrict(target))
			{
				PrintToChat2(client, "%t", "Client is unavailbale");
				return 0;
			}

			BanLengthMenu(client, target);
		}
	}
	return 0;
}


void BanLengthMenu(int client, int target)
{
	SetGlobalTransTarget(client);

	char buffer[256];
	char buffer2[16];
	
	Menu menu = new Menu(BanLengthMenu_Handler, MenuAction_Cancel | MenuAction_End | MenuAction_Select);
	menu.SetTitle("%t", "Ban length title", target);

	IntToString(GetClientUserId(target), buffer2, sizeof(buffer2));
	
	for(int i; i < 6; i++)
	{
		if(i < 5)
		{
			FormatEx(buffer, sizeof(buffer), "%t", "Minutes",	i == 0 ?	10:
																i == 1 ?	60:
																i == 2 ?	1440:
																i == 3 ?	10080:40320);
		}
		else
		{
			FormatEx(buffer, sizeof(buffer), "%t", "Permanently");
		}
		menu.AddItem(buffer2, buffer);
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, 0);
}

public int BanLengthMenu_Handler(Menu menu, MenuAction action, int client, int index)
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
				BanMenu(client);
			}
		}
		case MenuAction_Select:
		{
			char buffer[16];
			menu.GetItem(index, buffer, sizeof(buffer));
			int target = GetClientOfUserId(StringToInt(buffer));

			if(target == 0 || !IsClientInGame(target) || RestrictClientHasRestrict(target))
			{
				PrintToChat2(client, "%t", "Client is unavailbale");
				return 0;
			}

			RestrictClientBan(target, client,	index == 0 ?	10:
												index == 1 ?	60:
												index == 2 ?	1440:
												index == 3 ?	10080:
												index == 4 ?	40320:-1);

			AdminMenu(client);
		}
	}
													
	return 0;
}

void BannedPlayersMenu(int client)
{
	SetGlobalTransTarget(client);

	char buffer[32];
	char buffer2[16];

	Menu menu = new Menu(BannedPlayersMenu_Handler, MenuAction_Cancel | MenuAction_End | MenuAction_Select);
	menu.SetTitle("%t", "Banned players title");
	
	int count = 0;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !Clients[i].Authorized || !RestrictClientHasRestrict(i))
			continue;

		GetClientName(i, buffer, sizeof(buffer));
		IntToString(GetClientUserId(i), buffer2, sizeof(buffer2));
		menu.AddItem(buffer2, buffer);
		count++;
	}
	
	if(count == 0)
	{
		AddMenuItem2(menu, ITEMDRAW_DISABLED, "", "%t", "No players");
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, 0);
}

public int BannedPlayersMenu_Handler(Menu menu, MenuAction action, int client, int index)
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
			char buffer[16];
			menu.GetItem(index, buffer, sizeof(buffer));
			int target = GetClientOfUserId(StringToInt(buffer));
		
			if(target == 0 || !IsClientInGame(target) || !RestrictClientHasRestrict(target))
			{
				AdminMenu(client);
				PrintToChat2(client, "\x07%s%t", Colors[COLOR_OTHER], "Client is unavailbale");
				return 0;
			}

			BannedPlayerMenu(client, target);
		}
	}
	
	return 0;
}


void BannedPlayerMenu(int client, int target)
{
	SetGlobalTransTarget(client);

	char buffer[256];
	char buffer2[16]; 
	bool normal;
	
	IntToString(GetClientUserId(target), buffer2, sizeof(buffer2));
	Menu menu = new Menu(BannedPlayerMenu_Handler, MenuAction_Cancel | MenuAction_End | MenuAction_Select);
	menu.SetTitle("%t", "Banned player title", target);
	FormatEx(buffer, sizeof(buffer), "%t", "Unban item"); 
	menu.AddItem(buffer2, buffer, (Restricts[target].Admin == Clients[client].Account || GetUserFlagBits(client) & ADMFLAG_ROOT) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	FormatEx(buffer, sizeof(buffer), "Admin SteamID: [U:1:%i]", Restricts[target].Admin);
	menu.AddItem("", buffer, ITEMDRAW_DISABLED);

	FormatEx(buffer, sizeof(buffer), "%t", "Duration");		
	
	if(Restricts[target].Expires == -1)
	{
		Format(buffer, sizeof(buffer), "%s: %t", buffer, "Permanently");
	}
	else
	{
		normal = true;
		Format(buffer, sizeof(buffer), "%s: %t", buffer, "Minutes", Restricts[target].Duration / 60);
	}
	
	menu.AddItem("", buffer, ITEMDRAW_DISABLED);
	
	if(normal)
	{
		FormatEx(buffer, sizeof(buffer), "%t: %t", "Expires", "Minutes", (Restricts[target].Expires - GetTime()) / 60);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, 0);
}

public int BannedPlayerMenu_Handler(Menu menu, MenuAction action, int client, int index)
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
				BannedPlayersMenu(client);
			}
		}
		case MenuAction_Select:
		{
			char buffer[32];
			menu.GetItem(index, buffer, sizeof(buffer));
			int target = GetClientOfUserId(StringToInt(buffer));
			
			if(target == 0 || !IsClientInGame(target) || !RestrictClientHasRestrict(target))
			{
				AdminMenu(client);
				PrintToChat2(client, "\x07%s%t", Colors[COLOR_OTHER], "Client is unavailbale");
				return 0;
			}
			
			RestrictClientUnBan(target, client);
			AdminMenu(client);
			
		}
	}
	
	return 0;
}

void TransferMenu(int client, bool map = false)
{
	SetGlobalTransTarget(client);

	char buffer[256];
	char buffer2[16];

	Menu menu = new Menu(TransferMenu_Handler, MenuAction_Cancel | MenuAction_End | MenuAction_Select);
	menu.SetTitle("%t", "Transfer title", map ? "Map":"Player");
	
	FormatEx(buffer, sizeof(buffer), "%t\n ", "Transfer type item");
	IntToString(view_as<int>(map), buffer2, sizeof(buffer2));
	menu.AddItem(buffer2, buffer);
	int count = 0;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !Clients[i].Authorized || IsFakeClient(i) || !IsPlayerAlive(i) || RestrictClientHasRestrict(i))
			continue;
			
		IntToString(GetClientUserId(i), buffer2, sizeof(buffer2));
		GetClientName(i, buffer, sizeof(buffer));
		menu.AddItem(buffer2, buffer);
		count++;
	}
	
	if(count == 0)
	{
		FormatEx(buffer, sizeof(buffer), "%t", "No players");
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, 0);
}

public int TransferMenu_Handler(Menu menu, MenuAction action, int client, int index)
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
			char buffer[16];
			menu.GetItem(0, buffer, sizeof(buffer));
			
			bool map = view_as<bool>(StringToInt(buffer));
			
			if(index == 0)
			{
				TransferMenu(client, !map);
				return 0;
			}
			menu.GetItem(index, buffer, sizeof(buffer));
			int receiver = GetClientOfUserId(StringToInt(buffer));
			
			if(receiver == 0 || !IsClientInGame(receiver) || !IsPlayerAlive(receiver) || RestrictClientHasRestrict(receiver))
			{
				TransferMenu(client, map);
				PrintToChat2(client, "\x07%s%t", Colors[COLOR_OTHER], "Client is unavailbale");
				return 0;
			}
			if(map)
			{
				TransferByMapMenu(client, receiver);
			}
			else
			{
				TransferByTargetMenu(client, receiver);
			}
		}
	}
	
	return 0;
}

void TransferByMapMenu(int client, int receiver)
{
	SetGlobalTransTarget(client);

	char buffer[2][64];

	Menu menu = new Menu(TransferByMapMenu_Handler, MenuAction_Cancel | MenuAction_End | MenuAction_Select);
	menu.SetTitle("%t", "Transfer by map title", receiver, "Map");
	
	int count = 0;
	for(int i = 0; i < Items_Count; i++)
	{
		if(!TransferIsValidItem(i) || Items[i].Owner)
			continue;

		FormatEx(buffer[0], sizeof(buffer[]), "%i_%i", GetClientUserId(receiver), i);
		menu.AddItem(buffer[0], Configs[Items[i].Config].Name);
		count++;

	}
	
	if(count == 0)
	{
		AddMenuItem2(menu, ITEMDRAW_DISABLED, "", "%t", "No items");
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, 0);
}

public int TransferByMapMenu_Handler(Menu menu, MenuAction action, int client, int index)
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
				TransferMenu(client, true);
			}
		}
		case MenuAction_Select:
		{
			char buffer[256];
			menu.GetItem(index, buffer, sizeof(buffer));
			
			int symbol = FindCharInString(buffer, '_');
			
			if(symbol == -1)
				return 0;
			
			int item = StringToInt(buffer[symbol + 1]);
			buffer[symbol] = 0;
			int receiver = GetClientOfUserId(StringToInt(buffer));
			
			if(receiver == 0 || !IsClientInGame(receiver) || !IsPlayerAlive(receiver) || RestrictClientHasRestrict(receiver))
			{
				PrintToChat2(client, "\x07%s%t", Colors[COLOR_OTHER], "Client is unavailbale");
				TransferMenu(client);
				return 0;
			}

			if(Items[item].Owner)
			{
				PrintToChat2(client, "\x07%s%t", Colors[COLOR_OTHER], "Materia is unavailbale");
				TransferMenu(client);
				return 0;
			}
			
			TransferItem(item, receiver, client);
			AdminMenu(client);
		}
	}
	
	return 0;
}


void TransferByTargetMenu(int client, int receiver)
{
	SetGlobalTransTarget(client);

	char buffer[256];
	char buffer2[256];

	Menu menu = new Menu(TransferByTargetMenu_Handler, MenuAction_Cancel | MenuAction_End | MenuAction_Select);
	menu.SetTitle("%t", "Transfer by target title", receiver, "Player");
	
	int count = 0;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !Clients[i].Authorized || IsFakeClient(i) || !IsPlayerAlive(i))
			continue;

		int item = -1;
		while((item = ItemFindClientItem(i, item)) != -1)
		{
			if(!TransferIsValidItem(item, receiver))
				continue;
				
			Format(buffer, sizeof(buffer), "%N\n• %s", i, Configs[Items[item].Config].ShortName);
			FormatEx(buffer2, sizeof(buffer2), "%i_%i_%i", GetClientUserId(receiver), GetClientUserId(i), item);
			menu.AddItem(buffer2, buffer);
			count++;
		}
	}
	
	if(count == 0)
	{
		FormatEx(buffer, sizeof(buffer), "%t", "No players");
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, 0);
}

public int TransferByTargetMenu_Handler(Menu menu, MenuAction action, int client, int index)
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
				TransferMenu(client);
			}
		}
		case MenuAction_Select:
		{
			char buffer[256];
			menu.GetItem(index, buffer, sizeof(buffer));
			
			int symbol = FindCharInString(buffer, '_', true);
			
			if(symbol == -1)
				return 0;
			
			int item = StringToInt(buffer[symbol + 1]);

			buffer[symbol] = 0;
			
			if((symbol = FindCharInString(buffer, '_')) == -1)
				return 0;
			
			int target = GetClientOfUserId(StringToInt(buffer[symbol + 1]));
			buffer[symbol] = 0;
			int receiver = GetClientOfUserId(StringToInt(buffer));
			
			if(target == 0 ||  receiver == 0 || !IsClientInGame(target) || !IsClientInGame(receiver) || !IsPlayerAlive(target) || !IsPlayerAlive(receiver) || RestrictClientHasRestrict(receiver))
			{
				PrintToChat2(client, "%t", "Client is unavailbale");
				TransferMenu(client);
				return 0;
			}
			if(Items[item].Owner != target)
			{
				PrintToChat2(client, "%t", "Materia is unavailbale");
				TransferMenu(client);
				return 0;
			}
			TransferItem(item, receiver, client);
			AdminMenu(client);
		}
	}
	
	return 0;
}

#if defined ASSIST_USE
void UseItemsMenu(int client)
{
	SetGlobalTransTarget(client);

	char buffer[2][256];
	Menu menu = new Menu(UseItemMenu_Handler, MenuAction_Cancel | MenuAction_End | MenuAction_Select);
	menu.SetTitle("%t", "Use items title");
	
	int count = 0;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !IsPlayerAlive(i) || !Clients[i].Authorized)
			continue;
			
		int item = -1;
		
		while((item = ItemFindClientItem(i, item)) != -1)
		{
			if(Items[item].Button)
			{
				FormatEx(buffer[0], sizeof(buffer[]), "%i_%i", GetClientUserId(i), item);
				FormatEx(buffer[1], sizeof(buffer[]), "%N\n-> %s", i, Configs[Items[item].Config].Name);
				menu.AddItem(buffer[0], buffer[1]);
				count++;
			}
		}
	}
	
	if(count == 0)
	{
		AddMenuItem2(menu, ITEMDRAW_DISABLED, "", "%t", "No players");
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, 0);
}

public int UseItemMenu_Handler(Menu menu, MenuAction action, int client, int index)
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
			char buffer[256];
			menu.GetItem(index, buffer, sizeof(buffer));
			
			int symbol = FindCharInString(buffer, '_');
			
			if(symbol == -1)
				return 0;
			
			int item = StringToInt(buffer[symbol + 1]);

			if(!Items[item].Button)
				return 0;

			buffer[symbol] = 0;
			int target = GetClientOfUserId(StringToInt(buffer));
			
			if(target == 0 || !IsClientInGame(target) || !IsPlayerAlive(target) || Items[item].Owner != target)
			{
				UseItemsMenu(client);
				PrintToChat2(client, "\x07%s%t", Colors[COLOR_OTHER], "Client is unavailbale");
				return 0;
			}
			AssistUseAdmin(item, client);
			AdminMenu(client);
		}
	}
	
	return 0;
}
#endif

bool EditedConfigs[MAX_CONFIGS];

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
				int config = StringToInt(buffer);
				if(EditedConfigs[config])
				{
					AdminMenu(client);
					return 0;
				}
				EditClientsConfigs[client].Init(config);
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

	if(!EditedConfigs[cfg])
	{
		EditedConfigs[cfg] = true;
	}

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
			EditedConfigs[EditClientsConfigs[client].Config] = false;
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
					EditedConfigs[EditClientsConfigs[client].Config] = false;
					RemoveConfig(EditClientsConfigs[client].Config);
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
			strcopy(Configs[cfg].Color[1], sizeof(Configs[].Color), args);
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
			Configs[cfg].Mode = StringToInt(args);
		}
		case 8:
		{
			Configs[cfg].Slot = StringToInt(args);
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
			Configs[cfg].Display = StringToInt(args);
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

void AdminConfigSave()
{
	char buffer[256];
	BuildPath(Path_SM, buffer, sizeof(buffer), "configs/entwatch/empty.cfg");
		
	KeyValues kv = new KeyValues("entities");
		
	if(!kv.ImportFromFile(buffer))
	{
		LogMessage("File %s not founded", buffer);
		return;
	}

	AdminConfigBrowseItems(kv);
		
	GetCurrentMap(buffer, sizeof(buffer));
	BuildPath(Path_SM, buffer, sizeof(buffer), "configs/entwatch/%s.cfg", buffer);
	kv.Rewind();
	kv.ExportToFile(buffer);
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
		kv.SetNum("cooldown", RoundToNearest(Configs[i].Cooldown));
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
		
				if(Configs[i].Slot == SLOT_PRIMARY || Configs[i].Slot == SLOT_SECONDARY)
				{
					kv.SetNum("allowtransfer", 1);
					kv.SetNum("forcedrop", 1);
				}
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