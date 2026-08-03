void StripperInit()
{
    RegServerCmd("sm_setcooldown", Command_SetCooldown);
    RegServerCmd("sm_setmaxuses", Command_SetMaxuses);
    RegServerCmd("sm_decuses", Command_DecUses);
}

// Эти команды вызываются из конфигов карт и stripper'а, где никто не увидит
// ошибку в чате - поэтому каждый отказ обязан попадать в лог. Иначе опечатка в
// hammerid тихо ничего не делает и выглядит как баг плагина.

public Action Command_SetCooldown(int args)
{
    if(args != 2)
    {
        LogError("sm_setcooldown: expected \"<weapon hammerid> <cooldown>\"");
        return Plugin_Handled;
    }

    char buffer[16];

    GetCmdArg(1, buffer, sizeof(buffer));
    int hammerid = StringToInt(buffer);

    GetCmdArg(2, buffer, sizeof(buffer));
    float cooldown = StringToFloat(buffer);

    if(cooldown < 0.0)
    {
        LogError("sm_setcooldown: negative cooldown %.1f for hammerid %i", cooldown, hammerid);
        return Plugin_Handled;
    }

    int config = ConfigGetByWeaponHammerId(hammerid);

    if(config == -1)
    {
        LogError("sm_setcooldown: no config with weapon hammerid %i", hammerid);
        return Plugin_Handled;
    }

    Configs[config].Cooldown = cooldown;

    return Plugin_Handled;
}

public Action Command_SetMaxuses(int args)
{
    if(args != 2)
    {
        LogError("sm_setmaxuses: expected \"<weapon hammerid> <maxuses>\"");
        return Plugin_Handled;
    }

    char buffer[16];

    GetCmdArg(1, buffer, sizeof(buffer));
    int hammerid = StringToInt(buffer);

    GetCmdArg(2, buffer, sizeof(buffer));
    int maxuses = StringToInt(buffer);

    // Отрицательный лимит делает предмет вечно израсходованным: ItemIsReady()
    // сравнивает Uses < Maxuses, и это никогда не станет истиной.
    if(maxuses < 0)
    {
        LogError("sm_setmaxuses: negative maxuses %i for hammerid %i", maxuses, hammerid);
        return Plugin_Handled;
    }

    int config = ConfigGetByWeaponHammerId(hammerid);

    if(config == -1)
    {
        LogError("sm_setmaxuses: no config with weapon hammerid %i", hammerid);
        return Plugin_Handled;
    }

    Configs[config].Maxuses = maxuses;

    return Plugin_Handled;
}

public Action Command_DecUses(int args)
{
    if(args != 1)
    {
        LogError("sm_decuses: expected \"<weapon hammerid>\"");
        return Plugin_Handled;
    }

    char buffer[16];

    GetCmdArg(1, buffer, sizeof(buffer));
    int hammerid = StringToInt(buffer);

    int item = ItemsGetByWeaponHammerID(hammerid);

    if(item == -1)
    {
        LogError("sm_decuses: no live item with weapon hammerid %i", hammerid);
        return Plugin_Handled;
    }

    if(Items[item].Uses > 0)
        Items[item].Uses--;

    return Plugin_Handled;
}
