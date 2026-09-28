void ConfigParse(const char[] map)
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/entwatch/%s.cfg", map);

    if(!ConfigLoad(path))
        return;

    APIOnConfigLoaded();
}

bool ConfigLoad(const char[] path)
{
    if(!FileExists(path))
        return false;

    KeyValues kv = new KeyValues("Config");

    if(!kv.ImportFromFile(path))
    {
        delete kv;
        return false;
    }

    #if defined HUD
    HudConfigLoad(kv);
    #endif

    #if defined ASSIST_USE
    AssistUseConfigLoad(kv);
    #endif

    ConfigBrowse(kv);
    delete kv;

    return true;
}

void ConfigBrowse(KeyValues kv)
{
    if(!kv.GotoFirstSubKey())
        return;

    do
    {
        ConfigBrowseKey(kv);
    }
    while(kv.GotoNextKey());
}

void ConfigBrowseKey(KeyValues kv)
{
    if(Configs_Count >= MAX_CONFIGS)
        return;

    int type = ConfigGetType(kv);
    switch(type)
    {
        case CONFIG_TYPE_GFL:    ConfigBrowseKeyGFL(kv);
        case CONFIG_TYPE_UNLOZE: ConfigBrowseKeyUNLOZE(kv);
    }
    
}

int ConfigGetType(KeyValues kv)
{
    int wpn_hammerid = kv.GetNum("hammerid");
    int wpn_hammerid2 = kv.GetNum("weaponid");

    if(wpn_hammerid > 0)
        return CONFIG_TYPE_GFL;

    if (wpn_hammerid2 > 0)
        return CONFIG_TYPE_UNLOZE;

    return CONFIG_TYPE_UNKNOWN;
}

void ConfigBrowseKeyGFL(KeyValues kv)
{
    int config = Configs_Count;
    ConfigInit(config, CONFIG_TYPE_GFL);
    Config c; c = Configs[Configs_Count];

    kv.GetString("spawn", c.Template, sizeof(c.Template));

    kv.GetString("name", c.Name, sizeof(c.Name));
    kv.GetString("shortname", c.ShortName, sizeof(c.ShortName));

    c.Color[0] = '#';
    kv.GetString("color", c.Color[1], sizeof(c.Color) - 1, Colors[COLOR_ITEM]);
    ColorNameToColorCode(c.Color, sizeof(c.Color));
    
    kv.GetString("filtername", c.Filter, sizeof(c.Filter));

    c.Weapon_HammerId = kv.GetNum("hammerid");

    c.Trigger_HammerId = kv.GetNum("triggerid");
    
    c.Button_HammerId = kv.GetNum("buttonid");
    c.Compare_HammerId = kv.GetNum("compareid");
    c.Relay_HammerId = kv.GetNum("relayid");

    if(kv.GetNum("chat", 1))       c.Display |= DISPLAY_CHAT;
    if(kv.GetNum("activate", 1))   c.Display |= DISPLAY_USE;
    if(kv.GetNum("hud", 1))        c.Display |= DISPLAY_HUD;
	
    c.Slot = (kv.GetNum("allowtransfer", 1) || kv.GetNum("forcedrop", 1)) ? SLOT_SECONDARY:SLOT_KNIFE;

    c.Mode = kv.GetNum("mode") - 1;

    if(c.Mode > MODE_CHARGESCD)
        c.Mode = MODE_PROTECT;
        
    if(c.Mode == MODE_PROTECT)
        c.Display &= ~(DISPLAY_USE);

    c.Maxuses = kv.GetNum("maxuses");
    c.Cooldown = kv.GetFloat("cooldown");

    Configs[Configs_Count++] = c;
}

void ConfigBrowseKeyUNLOZE(KeyValues kv)
{
    int config = Configs_Count;
    ConfigInit(config, CONFIG_TYPE_UNLOZE);
    Config c; c = Configs[Configs_Count];

    kv.GetString("spawn", c.Template, sizeof(c.Template));

    kv.GetString("name", c.Name, sizeof(c.Name));
    kv.GetString("short", c.ShortName, sizeof(c.ShortName));

    c.Color[0] = '#';
    kv.GetString("color", c.Color[1], sizeof(c.Color) - 1, Colors[COLOR_ITEM]);

    kv.GetString("filter", c.Filter, sizeof(c.Filter));
    
    c.Weapon_HammerId = kv.GetNum("weaponid");

    c.Trigger_HammerId = kv.GetNum("triggerid");

    c.Button_HammerId = kv.GetNum("buttonid");
    c.Compare_HammerId = kv.GetNum("compareid");
    c.Relay_HammerId = kv.GetNum("relayid");

    c.Display = kv.GetNum("display", DISPLAY_DEFAULT);
    c.Slot = kv.GetNum("slot", SLOT_DEFAULT);

    c.Mode = kv.GetNum("mode", MODE_DEFAULT);
    
    if(c.Mode > MODE_CHARGESCD)
        c.Mode = MODE_PROTECT;

    if(c.Mode == MODE_PROTECT)
        c.Display &= ~(DISPLAY_USE);

    c.Maxuses = kv.GetNum("maxuses");
    c.Cooldown = kv.GetFloat("cooldown");

    Configs[Configs_Count++] = c;
}

