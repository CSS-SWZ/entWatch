#if !defined ADMIN_MENU
	#endinput
#endif

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
	
	for(int i; i < 7; i++)
	{
		if(i < 5)
		{
			FormatEx(buffer, sizeof(buffer), "%t", "Minutes",	i == 0 ?	10:
																i == 1 ?	60:
																i == 2 ?	1440:
																i == 3 ?	10080:40320);
		}
		else if(i == 5)
		{
			FormatEx(buffer, sizeof(buffer), "%t", "Permanently");
		}
		else
		{
			FormatEx(buffer, sizeof(buffer), "%t", "Temporary");
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

			if(index == 6)
			{
				RestrictClientTempBan(target, client);
			}
			else
			{
				RestrictClientBan(target, client,	index == 0 ?	10:
													index == 1 ?	60:
													index == 2 ?	1440:
													index == 3 ?	10080:
													index == 4 ?	40320:-1);
			}

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

	// У временного рестрикта нет ни выдавшего админа, ни строки в базе, поэтому
	// снять его разрешено любому, кому доступна команда - то же правило, что и в
	// RestrictClientUnBan(). Без этой ветки пункт рисовался бы серым: сравнение
	// с Restricts[].Admin == 0 не проходит ни у кого, и меню, которым рестрикт
	// выдали, не могло бы его же и снять.
	if(Restricts[target].Temporary)
	{
		menu.AddItem(buffer2, buffer);

		FormatEx(buffer, sizeof(buffer), "%t: %t", "Duration", "Temporary");
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);

		menu.ExitBackButton = true;
		menu.Display(client, 0);
		return;
	}

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

