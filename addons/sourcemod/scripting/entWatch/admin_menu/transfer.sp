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

		FormatEx(buffer[0], sizeof(buffer[]), "%i_%i", GetClientUserId(receiver), ItemGetRef(i));
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
			
			int item = ItemsGetByRef(StringToInt(buffer[symbol + 1]));
			buffer[symbol] = 0;
			int receiver = GetClientOfUserId(StringToInt(buffer));
			
			if(receiver == 0 || !IsClientInGame(receiver) || !IsPlayerAlive(receiver) || RestrictClientHasRestrict(receiver))
			{
				PrintToChat2(client, "\x07%s%t", Colors[COLOR_OTHER], "Client is unavailbale");
				TransferMenu(client);
				return 0;
			}

			// Предмета уже нет: карта убрала оружие, пока меню было открыто.
			if(item == -1)
			{
				PrintToChat2(client, "\x07%s%t", Colors[COLOR_OTHER], "Item is unavailbale");
				TransferMenu(client);
				return 0;
			}

			if(Items[item].Owner)
			{
				PrintToChat2(client, "\x07%s%t", Colors[COLOR_OTHER], "Item is unavailbale");
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
			FormatEx(buffer2, sizeof(buffer2), "%i_%i_%i", GetClientUserId(receiver), GetClientUserId(i), ItemGetRef(item));
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
			
			int item = ItemsGetByRef(StringToInt(buffer[symbol + 1]));

			// Предмета уже нет: карта убрала оружие, пока меню было открыто.
			if(item == -1)
			{
				PrintToChat2(client, "%t", "Item is unavailbale");
				TransferMenu(client);
				return 0;
			}

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
				PrintToChat2(client, "%t", "Item is unavailbale");
				TransferMenu(client);
				return 0;
			}
			TransferItem(item, receiver, client);
			AdminMenu(client);
		}
	}
	
	return 0;
}

