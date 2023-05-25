#define MAX_CONFIGS         50


// Display
#define DISPLAY_CHAT        (1 << 0)
#define DISPLAY_USE         (1 << 1)
#define DISPLAY_HUD         (1 << 2)

// Slot
#define SLOT_NONE           0
#define SLOT_PRIMARY        1
#define SLOT_SECONDARY      2
#define SLOT_KNIFE          3
#define SLOT_GRENADES       4

// Button mode
#define MODE_PROTECT        0
#define MODE_COOLDOWN       1
#define MODE_MAXUSES        2
#define MODE_MAXUSESCD      3
#define MODE_CHARGESCD      4

// Default
#define DISPLAY_DEFAULT     DISPLAY_CHAT|DISPLAY_USE|DISPLAY_HUD
#define SLOT_DEFAULT        SLOT_SECONDARY
#define MODE_DEFAULT        MODE_COOLDOWN

#define CONFIG_TYPE_UNKNOWN 0
#define CONFIG_TYPE_GFL     1
#define CONFIG_TYPE_UNLOZE  2

int Configs_Count;
Config Configs[MAX_CONFIGS];

void ConfigOnMapStart()
{
    ConfigClearAll();

    char map[64];
    GetCurrentMap(map, sizeof(map));
    ConfigParse(map);
}

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
        return false;

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
    kv.GetString("color", c.Color[1], sizeof(c.Color), Colors[COLOR_ITEM]);
    
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
    kv.GetString("color", c.Color[1], sizeof(c.Color));

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

void ConfigOnMapEnd()
{
    ConfigClearAll();
}

void ConfigClearAll()
{
    if(!Configs_Count)
        return;

    for(int i = 0; i < Configs_Count; i++)
    {
        ConfigClear(i);
    }
    Configs_Count = 0;
}

stock int ConfigGetByWeaponHammerId(int hammerid)
{
    for(int i = 0; i < Configs_Count; i++)
    {
        if(Configs[i].Weapon_HammerId == hammerid)
            return i;
    }

    return -1;
}

stock int ConfigGetByName(const char[] name)
{
    int len = strlen(name);
    for(int i = 0; i < Configs_Count; i++)
    {
        if(strncmp(Configs[i].Name, name, len, false) == 0)
            return i;
    }

    return -1;
}

stock int ConfigGetByShortName(const char[] name)
{
    int len = strlen(name);
    for(int i = 0; i < Configs_Count; i++)
    {
        if(strncmp(Configs[i].ShortName, name, len, false) == 0)
            return i;
    }

    return -1;
}

stock int ConfigGetByNames(const char[] name)
{
    int item = -1;

    item = ConfigGetByName(name);

    if(item != -1)
        return item;

    item = ConfigGetByShortName(name);
    
    if(item != -1)
        return item;

    return -1;
}

void ConfigInit(int config, int type)
{
    ConfigClear(config);
    Configs[config].Type = type;
}

void ConfigClear(int config)
{
    Configs[config].Type = CONFIG_TYPE_UNKNOWN;
    Configs[config].Weapon_HammerId = 0;
    Configs[config].Trigger_HammerId = 0;
    Configs[config].Button_HammerId = 0;
    Configs[config].Compare_HammerId = 0;
    Configs[config].Relay_HammerId = 0;
    Configs[config].Name[0] = 0;
    Configs[config].ShortName[0] = 0;
    Configs[config].Filter[0] = 0;
    Configs[config].Display = 0;
    Configs[config].Slot = SLOT_DEFAULT;
    Configs[config].Mode = MODE_COOLDOWN;
    Configs[config].Maxuses = 0;
    Configs[config].Cooldown = 0.0;
    Configs[config].Template[0] = 0;
    Configs[config].Color[0] = '#';

    strcopy(Configs[config].Color[1], sizeof(Configs[].Color), Colors[COLOR_ITEM]);
}

bool ConfigGetDisplay(int config, int display)
{
    return !!(Configs[config].Display & display);
}