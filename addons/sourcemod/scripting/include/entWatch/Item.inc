#if defined entWatch_Item_included
	#endinput
#endif

#define entWatch_Item_included

enum struct Item
{
    int Config;

    int Weapon;
    int Trigger;
    
    int Button;
    int Compare;
    int Relay;

    int Owner;

    int Uses;

    float Cooldown;

    bool Transfered;
    bool RemovedButton;
}