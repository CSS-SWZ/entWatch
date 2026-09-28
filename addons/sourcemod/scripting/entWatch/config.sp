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

#include "config/parse.sp"
#include "config/save.sp"

void ConfigOnMapStart()
{
    ConfigClearAll();

    char map[64];
    GetCurrentMap(map, sizeof(map));
    StringToLowercase(map);
    ConfigParse(map);
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

    // Пустая строка не должна совпадать ни с чем: strncmp() с нулевой длиной
    // возвращает 0 и вернул бы первый попавшийся конфиг.
    if(len == 0)
        return -1;

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

stock void RemoveConfig(int config)
{
	for(int i = config; i < Configs_Count - 1; i++)
	{
		Configs[i] = Configs[i + 1];
	}

	Configs_Count--;

	RemoveItemByConfig(config);
}

