void TransferInit()
{
	RegAdminCmd("sm_etransfer", Command_Transfer, ADMFLAG_GENERIC);
}

public Action Command_Transfer(int client, int args)
{
    if(args != 2)
    {
    	ReplyToCommand(client, "%t %t!\nSyntax: sm_etransfer <owner/$item> <receiver>", "Tag", "Incorrect usage");
        return Plugin_Handled;
    }   
    char buffer[64];
    GetCmdArg(2, buffer, 64);
    int receiver = FindTarget(client, buffer, true, false);    

    if(receiver <= 0 || RestrictClientHasRestrict(receiver) || !Clients[receiver].Authorized)
    	return Plugin_Handled;

    int item = -1;
    GetCmdArg(1, buffer, 64);
    if(buffer[0] == '$')
    {
        item = ItemsGetByShortName(buffer[1]);

        if(item != -1)
            TransferItem(item, receiver, client);   
    }
    else
    {
    	int owner = FindTarget(client, buffer, true, false);
    	if(owner > 0)
    	{
            while((item = ItemFindClientItem(owner, item)) != -1)
            {
                TransferItem(item, receiver, client);
            }
    	}
    }

    return Plugin_Handled;
}

bool TransferIsValidItem(int item, int receiver = 0)
{
    if(Items[item].Weapon == 0)
        return false;
        
    if(receiver && Items[item].Owner == receiver)
        return false;

    if(Configs[Items[item].Config].Slot == SLOT_NONE || Configs[Items[item].Config].Slot == SLOT_KNIFE)
        return false;

    return true;
}

bool TransferItem(int item, int receiver, int admin)
{
    if(!TransferIsValidItem(item, receiver))
        return false;

    int owner = Items[item].Owner;
    if(owner)
    {
    	ItemDrop(item);
    	char buffer[32];
    	GetEntityClassname(Items[item].Weapon, buffer, sizeof(buffer));
    	GivePlayerItem(owner, buffer);
    
    	PrintToChatAll2("\x07%s%N \x07%s%t \x07%s%s \x07%s[\x07%s%N \x07%s→ \x07%s%N\x07%s]", Colors[COLOR_NAME], admin, Colors[COLOR_OTHER], "Transfered", Configs[Items[item].Config].Color[1], Configs[Items[item].Config].Name, Colors[COLOR_OTHER], Colors[COLOR_NAME], owner, Colors[COLOR_OTHER], Colors[COLOR_NAME], receiver, Colors[COLOR_OTHER]);
    
    	LogAction(admin, receiver, "%N (%s) transfered \"%s\" [%N to %N].", admin, Clients[admin].SteamID, Configs[Items[item].Config].Name, owner, receiver);
    }
    else
    {
    	PrintToChatAll2("\x07%s%N \x07%s%t \x07%s%s \x07%s[%t → %N\x07%s]", Colors[COLOR_NAME], admin, Colors[COLOR_OTHER], "Transfered", Configs[Items[item].Config].Color[1], Configs[Items[item].Config].Name, Colors[COLOR_OTHER], "Map", receiver, Colors[COLOR_OTHER]);
    
    	LogAction(admin, receiver, "%N (%s) transfered \"%s\" [MAP to %N].", admin, Clients[admin].SteamID, Configs[Items[item].Config].Name, receiver);    
    }

    bool display = ConfigGetDisplay(Items[item].Config, DISPLAY_CHAT);
    Configs[Items[item].Config].Display &= ~(DISPLAY_CHAT);
    EquipPlayerWeapon(receiver, Items[item].Weapon);
    FireEntityOutput(Items[item].Weapon, "OnPlayerPickup", receiver);
    Items[item].Transfered = true;

    if(display)
    {
    	Configs[Items[item].Config].Display |= DISPLAY_CHAT;
    }

    return true;
}

void TransferOnRoundEnd()
{
    TransferDropAllTransferedItems();
}

void TransferOnPluginEnd()
{
    TransferDropAllTransferedItems();
}

void TransferDropAllTransferedItems()
{
    for(int i = 0; i < Items_Count; i++)
    {
        if(Items[i].Transfered)
        {
            ItemDrop(i);
            Items[i].Transfered = false;
        }
    }
}