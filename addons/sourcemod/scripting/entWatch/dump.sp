void DumpInit()
{
    RegAdminCmd("sm_edump", Command_Dump, ADMFLAG_RCON);
}

public Action Command_Dump(int client, int args)
{
    if(Configs_Count)
    {
        PrintToConsole(client, "Config list:");
        for(int i = 0; i < Configs_Count; i++)
        {
            PrintToConsole(client, "#%i %s", i, Configs[i].Name);
        }

        if(Items_Count)
        {
            PrintToConsole(client, "Items list:");
            for(int i = 0; i < Items_Count; i++)
            {
                PrintToConsole(client, "%s (ID = %i, W: %i, C: %i, B: %i (locked = %i), [%i/%i])", Configs[Items[i].Config].Name, Items[i].Config, Items[i].Weapon, Items[i].Compare, Items[i].Button, HasEntProp(Items[i].Button, Prop_Data, "m_bLocked") ? GetEntProp(Items[i].Button, Prop_Data, "m_bLocked"):-1, Items[i].Uses, Configs[Items[i].Config].Maxuses);
            }
        }
    }

    return Plugin_Handled;
}