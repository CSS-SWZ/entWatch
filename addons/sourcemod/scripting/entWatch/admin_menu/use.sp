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
				FormatEx(buffer[0], sizeof(buffer[]), "%i_%i", GetClientUserId(i), ItemGetRef(item));
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
			
			int item = ItemsGetByRef(StringToInt(buffer[symbol + 1]));

			// Предмета уже нет: карта убрала оружие, пока меню было открыто.
			if(item == -1 || !Items[item].Button)
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

