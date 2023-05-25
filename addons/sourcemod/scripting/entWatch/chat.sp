

enum
{
	ACTION_PICK,
	ACTION_DROP,
	ACTION_USE,
	ACTION_DEATH,
	ACTION_DISCONNECT
}

void PrintToChatItemAction(int item, int action)
{
	char key[16];
	switch(action)
	{
		case ACTION_PICK:
		{
			if(!ConfigGetDisplay(Items[item].Config, DISPLAY_CHAT))
				return;

			strcopy(key, sizeof(key), "Pick");
		}
		case ACTION_DROP:
		{
			if(!ConfigGetDisplay(Items[item].Config, DISPLAY_CHAT))
				return;

			strcopy(key, sizeof(key), "Drop");
		}
		case ACTION_DEATH:
		{
			if(!ConfigGetDisplay(Items[item].Config, DISPLAY_CHAT))
				return;

			strcopy(key, sizeof(key), "Death");

		}
		case ACTION_DISCONNECT:
		{
			if(!ConfigGetDisplay(Items[item].Config, DISPLAY_CHAT))
				return;

			strcopy(key, sizeof(key), "Disconnect");

		}
		case ACTION_USE:
		{
			if(!ConfigGetDisplay(Items[item].Config, DISPLAY_USE))
				return;

			strcopy(key, sizeof(key), "Use");
		}

	}

	int team = GetClientTeam(Items[item].Owner);
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || IsFakeClient(i))
			continue;

		int team2 = GetClientTeam(i);

		if(team2 > 1 && team != team2)
			continue;

		PrintToChat2(i, "\x07%s%N (%s) \x07%s%t \x07%s%s",	Colors[COLOR_NAME],
															Items[item].Owner,
															Clients[Items[item].Owner].SteamID,
															Colors[COLOR_OTHER],
															key,
															Configs[Items[item].Config].Color[1],
															Configs[Items[item].Config].Name);
	}
}

stock void PrintToTeam(int team, const char[] format, any ...)
{
	int len = strlen(format) + 255;
	char[] buffer = new char[len];
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || IsFakeClient(i))
			continue;

		int team2 = GetClientTeam(i);

		if(team2 > 1 && team != team2)
			continue;
		
		SetGlobalTransTarget(i);
		VFormat(buffer, len, format, 3);
		SendMessage(i, buffer, len);
	}
}

void PrintToChat2(int client, const char[] message, any ...)
{
	int len = strlen(message) + 255;
	char[] buffer = new char[len];
	SetGlobalTransTarget(client);
	VFormat(buffer, len, message, 3);
	if(client == 0)
	{
		PrintToConsole(client, buffer);
	}
	else
	{
		SendMessage(client, buffer, len);
	}
}


stock void PrintToChatAll2(const char[] message, any ...)
{
	int len = strlen(message) + 255;
	char[] buffer = new char[len];
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			SetGlobalTransTarget(i);
			VFormat(buffer, len, message, 2);
			SendMessage(i, buffer, len);
		}
	}
}


void SendMessage(int client, char[] buffer, int iSize)
{
	static int mode = -1;
	if(mode == -1)
	{
		mode = view_as<int>(GetUserMessageType() == UM_Protobuf);
	}
	SetGlobalTransTarget(client);
	Format(buffer, iSize, "\x01\x07%s%t \x07%s%s", Colors[COLOR_TAG], "Tag", Colors[COLOR_OTHER], buffer);
	ReplaceString(buffer, iSize, "{C}", "\x07");

	
	Handle hMessage = StartMessageOne("SayText2", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
	switch(mode)
	{
		case 0:
		{
			BfWrite bfWrite = UserMessageToBfWrite(hMessage);
			bfWrite.WriteByte(client);
			bfWrite.WriteByte(true);
			bfWrite.WriteString(buffer);
		}
		case 1:
		{
			Protobuf protoBuf = UserMessageToProtobuf(hMessage);
			protoBuf.SetInt("ent_idx", client);
			protoBuf.SetBool("chat", true);
			protoBuf.SetString("msg_name", buffer);
			for(int k;k < 4;k++)	
				protoBuf.AddString("params", "");
		}
	}
	EndMessage();
}