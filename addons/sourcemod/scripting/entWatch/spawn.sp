void SpawnInit()
{
	RegAdminCmd("sm_espawn", Command_Spawn, ADMFLAG_BAN);
}

public Action Command_Spawn(int client, int args)
{
    if(args < 1)
    {
        ReplyToCommand(client, "%t %t!\nSyntax: sm_espawnitem <itemname> [receiver]", "Tag", "Incorrect usage");
        return Plugin_Handled;
    }

    char buffer[64];
    GetCmdArg(1, buffer, sizeof(buffer));

    int item = ConfigGetByShortName(buffer);

    if(item == -1)
        return Plugin_Handled;

    int receiver = client;
    if(args > 1)
    {
        GetCmdArg(2, buffer, sizeof(buffer));

        receiver = FindTarget(client, buffer, false, false);

        if(receiver == -1)
            return Plugin_Handled;
    }

    SpawnItem(item, receiver, client);
    return Plugin_Handled;
}

// DarkerZ entwatch
bool SpawnItem(int config, int receiver, int admin)
{
    if(!Configs[config].Template)
    	return false;
    
    int entity = -1;
    bool found;
    char buffer[256];
    while ((entity = FindEntityByClassname(entity, "point_template")) != -1)
    {
    	if(!GetEntPropString(entity, Prop_Data, "m_iName", buffer, sizeof(buffer)))
            continue;
    
    	if(strcmp(Configs[config].Template, buffer) == 0)
    	{
    		found = true;
    		break;
    	}
    }
    
    if(!found)
        return false;
    
    if((entity = CreateEntityByName("env_entity_maker")) == -1)
        return false;
    
    
    float origin[3];
    GetClientAbsOrigin(receiver, origin);
    origin[2] += 20.0;
    
    DispatchKeyValue(entity, "EntityTemplate", Configs[config].Template);
    DispatchKeyValue(entity, "spawnflags", "0");
    DispatchSpawn(entity);
    TeleportEntity(entity, origin, NULL_VECTOR, NULL_VECTOR);
    AcceptEntityInput(entity, "ForceSpawn");
    AcceptEntityInput(entity, "Kill");
    	
    PrintToChatAll2("\x07%s%N \x07%s%t \x07%s%s", Colors[COLOR_NAME], admin, Colors[COLOR_OTHER], "Spawned", Configs[config].Color[1], Configs[config].Name);
    LogMessage("Item %s spawned by %N", Configs[config].Name, admin);
    return true;
}