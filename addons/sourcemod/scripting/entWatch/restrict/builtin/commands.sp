public Action Command_Status(int client, int args)
{
	int target = client;
	
	char buffer[64];
	if(args)
	{
		GetCmdArg(1, buffer, sizeof(buffer));
		target = FindTarget(client, buffer, true, false);
		
		if(target <= 0)
		{
			target = client;
			return Plugin_Handled;
		}
		else if(target != client)
		{
			Format(buffer, 64, " (%N)", target);
		}
		else
		{
			buffer[0] = 0;
		}
	}
	if(Clients[target].Authorized)
	{
		if(RestrictClientHasRestrict(target))
		{
			char buffer2[256];
			SetGlobalTransTarget(client);

			// У временного рестрикта нет ни срока, ни строки в базе, поэтому
			// длительность для него пишется отдельно.
			if(Restricts[target].Temporary)
			{
				FormatEx(buffer2, sizeof(buffer2), "%t", "Temporary");
			}
			else
			{
				int duration = Restricts[target].Expires != -1 ? ((Restricts[target].Expires - GetTime()) / 60):-1;
				RestrictFormatDuration(buffer2, sizeof(buffer2), duration, true);
			}

			PrintToChat2(client, "%t%s", "You have restrict", buffer2, buffer);
		}
		else
		{
			PrintToChat2(client, "%t%s", "You have not restrict", buffer);
		}
	}
	else
	{
		PrintToChat2(client, "%t%s", "You were not logged in to the database", buffer);
	}
	
	return Plugin_Handled;
}

public Action Command_Ban(int client, int args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "%t %t!\nSyntax: sm_eban <#name|#userid> [minutes]", "Tag", "Incorrect usage");
	}
	else
	{
		char buffer[64];
		GetCmdArg(1, buffer, sizeof(buffer));

		int target = FindTarget(client, buffer, true, true);

		if(target > 0)
		{
			// Без второго аргумента - временный рестрикт, до смены карты.
			if(args == 1)
			{
				RestrictClientTempBan(target, client);
			}
			else
			{
				GetCmdArg(2, buffer, sizeof(buffer));
				RestrictClientBan(target, client, StringToInt(buffer));
			}
		}
	}
	
	return Plugin_Handled;
}

public Action Command_UnBan(int client, int args)
{
	if(args != 1)
	{
		ReplyToCommand(client, "%t %t!\nSyntax: sm_uneban <#name|#userid>", "Tag", "Incorrect usage");
	}
	else
	{
		char buffer[64];
		GetCmdArg(1, buffer, sizeof(buffer));
		
		int target = FindTarget(client, buffer, true, false);
		
		if(target > 0)
		{
			RestrictClientUnBan(target, client);
		}
	}
	
	return Plugin_Handled;
}

public Action Command_AddBan(int client, int args)
{
    if(args < 2)
    {
    	ReplyToCommand(client, "%t %t!\nSyntax: sm_addeban <minutes> [steamid] [ip]", "Tag", "Incorrect usage");
    }
    else
    {
    	char buffer[64];
        char ip[16];
    	GetCmdArg(1, buffer, sizeof(buffer));
    	int duration = StringToInt(buffer);
    	GetCmdArg(2, buffer, sizeof(buffer));
    	GetCmdArg(3, ip, sizeof(ip));
    	RestrictAddBan(duration, buffer, ip, client);
    }
    return Plugin_Handled;
}


public Action Command_DeleteBan(int client, int args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "%t %t!\nSyntax: sm_deleban [steamid] [ip]", "Tag", "Incorrect usage");
	}
	else
	{
		char steamid[64], ip[16];
		GetCmdArg(1, steamid, sizeof(steamid));
		GetCmdArg(2, ip, sizeof(ip));
		RestrictDeleteBan(steamid, ip, client);
	}
	return Plugin_Handled;
}

