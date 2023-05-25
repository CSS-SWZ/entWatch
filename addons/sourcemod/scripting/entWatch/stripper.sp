void StripperInit()
{
    RegServerCmd("sm_setcooldown", Command_SetCooldown);
    RegServerCmd("sm_setmaxuses", Command_SetMaxuses);
    RegServerCmd("sm_decuses", Command_DecUses);
}

public Action Command_SetCooldown(int args)
{
    if(args != 2)
        return Plugin_Handled;

    char buffer[16];

    GetCmdArg(1, buffer, sizeof(buffer));
    int hammerid = StringToInt(buffer);

    GetCmdArg(2, buffer, sizeof(buffer));
    float cooldown = StringToFloat(buffer);

    int config = ConfigGetByWeaponHammerId(hammerid);

    if(config == -1)
        return Plugin_Handled;

    Configs[config].Cooldown = cooldown;

    return Plugin_Handled;
}

public Action Command_SetMaxuses(int args)
{
    if(args != 2)
        return Plugin_Handled;

    char buffer[16];

    GetCmdArg(1, buffer, sizeof(buffer));
    int hammerid = StringToInt(buffer);

    GetCmdArg(2, buffer, sizeof(buffer));
    int maxuses = StringToInt(buffer);

    int config = ConfigGetByWeaponHammerId(hammerid);

    if(config == -1)
        return Plugin_Handled;

    Configs[config].Maxuses = maxuses;

    return Plugin_Handled;
}

public Action Command_DecUses(int args)
{
    if(args != 1)
        return Plugin_Handled;

    char buffer[16];

    GetCmdArg(1, buffer, sizeof(buffer));
    int hammerid = StringToInt(buffer);

    int item = ItemsGetByWeaponHammerID(hammerid);

    if(item == -1)
        return Plugin_Handled;

    if(Items[item].Uses > 0)
        Items[item].Uses--;

    return Plugin_Handled;
}