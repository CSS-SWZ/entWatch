// Закомментируйте define, чтобы собрать плагин без модуля.
#define HUD
#define ASSIST_USE
#define ADMIN_MENU
#define HALFZOMBIE

// Рестрикты - не больше одного define. Без обоих рестриктов нет (restrict/none.sp).
// Встроенная система: своя база ebans и временные рестрикты (restrict/builtin.sp).
//#define RESTRICT_BUILTIN

// Рестрикты из ядра RestrictCore, вид entwatch.pickup (restrict/core.sp).
#define RESTRICT_CORE

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
