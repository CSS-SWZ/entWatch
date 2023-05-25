#if defined entWatch_Config_included
	#endinput
#endif

#define entWatch_Config_included

enum struct Config
{
    int Type;

    int Weapon_HammerId;
    int Trigger_HammerId;
    
    int Button_HammerId;
    int Compare_HammerId;
    int Relay_HammerId;

    char Name[64];
    char ShortName[32];

    char Color[16];

    char Filter[64];

    int Display;
    int Slot;
    int Mode;
    int Maxuses;
    float Cooldown;

    char Template[64];
}