// Закомментируйте define, чтобы собрать плагин без модуля.
#define HUD
#define ASSIST_USE
#define ADMIN_MENU
#define HALFZOMBIE

void ModulesInit()
{
    #if defined HUD
    HudInit();
    #endif

    #if defined HALFZOMBIE
    HookEvent("player_spawn", OnPlayerSpawn);
    HookEvent("player_team", OnPlayerTeam);
    #endif

    #if defined ASSIST_USE
    AssistUseInit();
    #endif

    #if defined ADMIN_MENU
    AdminMenuInit();
    #endif
}
