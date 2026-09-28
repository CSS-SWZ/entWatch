enum struct Restrict
{
    int Count;
    int TotalDuration;

    // Current restrict
    int Admin;
    int Duration;
    int Expires;

    // Кэш членства в TempRestricts[]. Не источник истины, а производная от него:
    // прочёсывать список на каждый вызов RestrictClientHasRestrict() нельзя, её
    // зовут с SDKHook_Touch, то есть каждый тик на каждого игрока в триггере.
    bool Temporary;

    void Clear()
    {
        this.Count = 0;
        this.TotalDuration = 0;
        this.Admin = 0;
        this.Duration = 0;
        this.Expires = 0;
        this.Temporary = false;
    }
}

Restrict Restricts[MAXPLAYERS + 1];

bool LastQueryEBanNotCompleted;

#include "builtin/database.sp"
#include "builtin/utils.sp"
#include "builtin/temp.sp"
#include "builtin/load.sp"
#include "builtin/ban.sp"
#include "builtin/unban.sp"
#include "builtin/offline.sp"
#include "builtin/commands.sp"
#include "builtin/menu.sp"

void RestrictOnAllPluginsLoaded()
{
}

void RestrictOnLibraryAdded(const char[] name)
{
    #pragma unused name
}

void RestrictOnLibraryRemoved(const char[] name)
{
    #pragma unused name
}

void RestrictInit()
{
    RegConsoleCmd("sm_status", Command_Status);

    RegAdminCmd("sm_eban",      Command_Ban,       ADMFLAG_GENERIC);
    RegAdminCmd("sm_uneban",    Command_UnBan,     ADMFLAG_GENERIC);
    RegAdminCmd("sm_addeban",   Command_AddBan,    ADMFLAG_RCON);
    RegAdminCmd("sm_deleban",   Command_DeleteBan, ADMFLAG_RCON);

    DatabaseConnect();
}

void RestrictOnClientDisconnect(int client)
{
    Restricts[client].Clear();
}

bool RestrictClientHasRestrict(int client)
{
	// Временный рестрикт проверяется до гейта по базе намеренно: он от неё не
	// зависит и обязан работать, когда её нет.
	if(Restricts[client].Temporary)
		return true;

	return RestrictClientHasDatabaseRestrict(client);
}

// Рестрикт из базы, без учёта временного. Нужен там, где эти два вида надо
// различать: у одного есть строка в базе и выдавший его админ, у другого нет
// ни того, ни другого.
bool RestrictClientHasDatabaseRestrict(int client)
{
	return (DBLoaded && (Restricts[client].Expires == -1 || Restricts[client].Expires > GetTime()));
}

