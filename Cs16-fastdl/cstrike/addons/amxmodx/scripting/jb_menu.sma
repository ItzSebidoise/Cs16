#include <amxmodx>
#include <cstrike>
#include <amxmisc>
#include <fakemeta>

#define PLUGIN "JB Kompletni System + Grab"
#define VERSION "2.1 - AllInOne"
#define AUTHOR "Seb1k & XxNamiyXx"

#define ADMIN_FLAG_REQUIRED ADMIN_KICK // Vlajka 'd' pro adminy

// ==========================================================
// KONFIGURACE BAN SYSTÉMU
// ==========================================================
#define USE_AMXBANS 1

#define CMD_CTBAN "amx_ctban #%d %d ^"%s^""
#define CMD_GAG   "amx_gag #%d %d abc ^"%s^""
#define CMD_BAN_AMXBANS "amx_ban %d ^"%s^" ^"%s^""
#define CMD_BAN_NORMAL  "amx_ban ^"%s^" %d ^"%s^""

// ==========================================================
// NASTAVENÍ INTEGROVANÉHO GRABU
// ==========================================================
#define GRAB_SPEED 5
#define GRAB_MIN_DIST 90
#define GRAB_FORCE 8
#define GRAB_THROW_FORCE 1500

// Identifikátory dat klienta pro Grab
#define GRABBED  0
#define GRABBER  1
#define GRAB_LEN 2
#define FLAGS    3

#define CDF_IN_PUSH   (1<<0)
#define CDF_IN_PULL   (1<<1)

new client_data[33][4];

// Menu Keys
const MAIN_MENU_KEYS = (1<<0) | (1<<1) | (1<<2) | (1<<3) | (1<<7) | (1<<8);
const TEAM_MENU_KEYS = (1<<0) | (1<<1) | (1<<2) | (1<<8);
const ADMIN_BASE_KEYS = (1<<0) | (1<<1) | (1<<8);
const ACTION_MENU_KEYS = (1<<0) | (1<<1) | (1<<2) | (1<<3) | (1<<8);
const OTAZKY_MENU_KEYS = (1<<0) | (1<<1) | (1<<2) | (1<<3) | (1<<8);
const TREST_MENU_KEYS = (1<<0) | (1<<1) | (1<<2) | (1<<3) | (1<<4) | (1<<5) | (1<<8);

// Globální proměnné
new g_iMaxPlayers;
new bool:g_bFirstJoin[33];

// Pro systém trestů
new g_iSelectedPlayer[33]; 
new g_iTargetTeam[33];     
new g_iPunishType[33];     
new g_iUnbanType[33];      
new g_szPunishLength[33][32]; 

// Pro admin list hráčů
new g_iAdminPlayers[33][32], g_iAdminPlayerCount[33];
new g_iAdminPage[33];

// HUD Synchronizace
new g_hudSyncOtazka, g_hudSyncTrest, g_hudSyncSay;

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);
    g_iMaxPlayers = get_maxplayers();
    
    // HUD
    g_hudSyncOtazka = CreateHudSyncObj();
    g_hudSyncTrest = CreateHudSyncObj();
    g_hudSyncSay = CreateHudSyncObj();
    
    // Klasické příkazy
    register_clcmd("chooseteam", "Cmd_OtevriMenu");
    
    // Záchytné body pro chat zprávy (HUD zpráva z admin menu)
    register_clcmd("ZadejHudZpravu", "Cmd_ZadejHudZpravu");
    
    // Admin příkazy & Grab
    register_clcmd("+grab", "Cmd_GrabStart", ADMIN_FLAG_REQUIRED); 
    register_clcmd("-grab", "Cmd_GrabEnd"); 
    register_clcmd("+push", "Cmd_PushStart", ADMIN_FLAG_REQUIRED);
    register_clcmd("-push", "Cmd_PushEnd");
    register_clcmd("+pull", "Cmd_PullStart", ADMIN_FLAG_REQUIRED);
    register_clcmd("-pull", "Cmd_PullEnd");
    register_clcmd("drop" , "Cmd_Throw");
    
    // ROZDĚLENÉ PŘÍKAZY PRO MENU
    register_clcmd("adminmenu", "Cmd_OtevriAdminMenu");
    register_clcmd("admintrest", "Cmd_OtevriAdminTrestDirect");
    register_clcmd("@", "Cmd_AdminSay");
    
    // Messagemode pro zadávání délky a důvodů
    register_clcmd("ZadejDelku", "Cmd_ZadejDelku");
    register_clcmd("ZadejDuvod", "Cmd_ZadejDuvod");
    register_clcmd("ZadejUnbanDuvod", "Cmd_ZadejUnbanDuvod");
    
    // Registrace Menu
    register_menucmd(register_menuid("HlavniMenu"), MAIN_MENU_KEYS, "Handle_HlavniMenu");
    register_menucmd(register_menuid("TeamMenu"), TEAM_MENU_KEYS, "Handle_TeamMenu");
    register_menucmd(register_menuid("ZakladniAdminMenu"), ADMIN_BASE_KEYS, "Handle_ZakladniAdminMenu");
    register_menucmd(register_menuid("AdminActionMenu"), ACTION_MENU_KEYS, "Handle_AdminActionMenu");
    register_menucmd(register_menuid("OtazkyMenu"), OTAZKY_MENU_KEYS, "Handle_OtazkyMenu");
    register_menucmd(register_menuid("PotrestatMenu"), TREST_MENU_KEYS, "Handle_PotrestatMenu");
    register_menucmd(register_menuid("AdminTrestList"), (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<6)|(1<<7)|(1<<8), "Handle_AdminTrestList");
    
    // Hlídání eventů pro Grab
    register_event("DeathMsg", "Event_DeathMsg", "a");
    register_forward(FM_PlayerPreThink, "fm_player_prethink");
    
    // Blokace starého team menu
    register_message(get_user_msgid("ShowMenu"), "Message_ShowMenu");
    register_message(get_user_msgid("VGUIMenu"), "Message_VGUIMenu");
}

public client_connect(id)
{
    g_bFirstJoin[id] = true;
    client_data[id][GRABBED] = 0;
    client_data[id][GRABBER] = 0;
}

public client_disconnect(id)
{
    kill_grab(id);
}

silent_kill(id)
{
    if(!is_user_connected(id) || !is_user_alive(id)) return;
    new iMsgBlock = get_msg_block(get_user_msgid("DeathMsg"));
    set_msg_block(get_user_msgid("DeathMsg"), BLOCK_ONCE);
    user_kill(id, 1);
    set_msg_block(get_user_msgid("DeathMsg"), iMsgBlock);
}

// ==========================================
// AUTOMATICKÉ NAPOJENÍ K VĚZŇŮM
// ==========================================
public Message_ShowMenu(msg_id, msg_dest, id)
{
    if(!g_bFirstJoin[id]) return PLUGIN_CONTINUE;
    static szMenuCode[32];
    get_msg_arg_string(4, szMenuCode, charsmax(szMenuCode));
    if(containi(szMenuCode, "Team_Select") != -1) 
    { 
        g_bFirstJoin[id] = false; 
        set_task(0.1, "Task_AutoJoinT", id); 
        return PLUGIN_HANDLED; 
    }
    return PLUGIN_CONTINUE;
}

public Message_VGUIMenu(msg_id, msg_dest, id)
{
    if(get_msg_arg_int(1) != 2) return PLUGIN_CONTINUE;
    if(g_bFirstJoin[id]) 
    { 
        g_bFirstJoin[id] = false; 
        set_task(0.1, "Task_AutoJoinT", id); 
        return PLUGIN_HANDLED; 
    }
    return PLUGIN_CONTINUE;
}

public Task_AutoJoinT(id)
{
    if(!is_user_connected(id)) return;
    engclient_cmd(id, "jointeam", "1");  
    engclient_cmd(id, "joinclass", "5"); 
}

// ==========================================
// HLAVNÍ MENU (KLÁVESA M)
// ==========================================
public Cmd_OtevriMenu(id)
{
    if(!is_user_connected(id)) return PLUGIN_CONTINUE;
    new iTeam = get_user_team(id);
    if(iTeam == 0 || iTeam == 3) { Cmd_OtevriTeamMenu(id); return PLUGIN_HANDLED; }
    
    new szMenu[512], iLen = 0;
    if(iTeam == 2) iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d==== \rBacharske menu \d====^n^n");
    else iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d==== \rVezenske menu \d====^n^n");

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r1. \y» \wHerni obchod^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r2. \y» \wVybrat Pohyb^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r3. \y» \wVybrat vzhled^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r4. \y» \wZmenit Team^n^n"); 
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r8. \y» \wPravidla^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r9. \y» \yZavrit menu^n");

    show_menu(id, MAIN_MENU_KEYS, szMenu, -1, "HlavniMenu");
    return PLUGIN_HANDLED;
}

public Handle_HlavniMenu(id, key)
{
    switch(key)
    {
        case 0: client_print(id, print_chat, "[JB] Obchod se pripravuje...");
        case 1: client_print(id, print_chat, "[JB] Pohyby se pripravuji...");
        case 2: client_print(id, print_chat, "[JB] Vzhledy se pripravuji...");
        case 3: Cmd_OtevriTeamMenu(id); 
        case 7: show_motd(id, "https://www.youtube.com", "Pravidla Serveru");
    }
    return PLUGIN_HANDLED;
}

public Cmd_OtevriTeamMenu(id)
{
    new iTs = 0, iCTs = 0, iSpecs = 0;
    for(new i = 1; i <= g_iMaxPlayers; i++) {
        if(!is_user_connected(i)) continue;
        switch(get_user_team(i)) { case 1: iTs++; case 2: iCTs++; case 3: iSpecs++; }
    }
    new iMaxCTs = (iTs >= 12) ? 4 : (iTs >= 9) ? 3 : (iTs >= 3) ? 2 : 1;
    new szMenu[512], iLen = 0;
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d==== \rVyber teamu \d====^n^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r1. \y» \wBachari \r[ \d%d/%d \r]^n", iCTs, iMaxCTs);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r2. \y» \wVezni \r[ \d%d/16 \r]^n", iTs);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r3. \y» \wSpectatori \r[ \d%d/16 \r]^n^n", iSpecs);
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r9. \y» \yZavrit menu^n");
    show_menu(id, TEAM_MENU_KEYS, szMenu, -1, "TeamMenu");
    return PLUGIN_HANDLED;
}

public Handle_TeamMenu(id, key)
{
    switch(key)
    {
        case 0: {
            new iTs = 0, iCTs = 0;
            for(new i = 1; i <= g_iMaxPlayers; i++) { if(!is_user_connected(i)) continue; if(get_user_team(i) == 1) iTs++; else if(get_user_team(i) == 2) iCTs++; }
            new iMaxCTs = (iTs >= 12) ? 4 : (iTs >= 9) ? 3 : (iTs >= 3) ? 2 : 1;
            if(iCTs >= iMaxCTs) { client_print(id, print_chat, "[JB] Tym Bacharu je plny!"); return PLUGIN_HANDLED; }
            if(is_user_alive(id)) silent_kill(id); cs_set_user_team(id, CS_TEAM_CT);
        }
        case 1: { if(is_user_alive(id)) silent_kill(id); cs_set_user_team(id, CS_TEAM_T); }
        case 2: { if(is_user_alive(id)) silent_kill(id); cs_set_user_team(id, CS_TEAM_SPECTATOR); }
    }
    return PLUGIN_HANDLED;
}

// ==========================================
// ADMIN MENU (adminmenu) - Více možností
// ==========================================
public Cmd_OtevriAdminMenu(id)
{
    if(!(get_user_flags(id) & ADMIN_FLAG_REQUIRED)) return PLUGIN_HANDLED;
    
    new szMenu[512], iLen = 0;
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d==== \rHlavni Admin Menu \d====^n^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r1. \y» \wPotrestat / Presunout hrace^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r2. \y» \wPoslat HUD zpravu na obrazovku^n^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r9. \y» \yZavrit menu^n");
    
    show_menu(id, ADMIN_BASE_KEYS, szMenu, -1, "ZakladniAdminMenu");
    return PLUGIN_HANDLED;
}

public Handle_ZakladniAdminMenu(id, key)
{
    switch(key)
    {
        case 0: { BuildAdminPlayerList(id); Cmd_AdmintrestList(id); }
        case 1: { client_cmd(id, "messagemode ZadejHudZpravu"); client_print(id, print_chat, "[JB] Napis text HUD zpravy pro vsechny:"); }
    }
    return PLUGIN_HANDLED;
}

// ==========================================
// ADMIN TREST MENU DIRECT (admintrest) - Jen trestací list
// ==========================================
public Cmd_OtevriAdminTrestDirect(id)
{
    if(!(get_user_flags(id) & ADMIN_FLAG_REQUIRED)) return PLUGIN_HANDLED;
    
    BuildAdminPlayerList(id);
    Cmd_AdmintrestList(id);
    return PLUGIN_HANDLED;
}

public Cmd_ZadejHudZpravu(id)
{
    new szArgs[128]; read_args(szArgs, charsmax(szArgs)); remove_quotes(szArgs); trim(szArgs);
    if(strlen(szArgs) > 0) {
        set_hudmessage(255, 255, 255, -1.0, 0.20, 0, 0.0, 5.0, 0.1, 0.2);
        ShowSyncHudMsg(0, g_hudSyncSay, "%s", szArgs);
    }
    return PLUGIN_HANDLED;
}

public Cmd_AdminSay(id)
{
    if(!(get_user_flags(id) & ADMIN_FLAG_REQUIRED)) return PLUGIN_HANDLED;
    new szArgs[128]; read_args(szArgs, charsmax(szArgs)); remove_quotes(szArgs);
    if(strlen(szArgs) > 0) {
        set_hudmessage(255, 255, 255, -1.0, 0.20, 0, 0.0, 5.0, 0.1, 0.2);
        ShowSyncHudMsg(0, g_hudSyncSay, "%s", szArgs);
    }
    return PLUGIN_HANDLED;
}

// ==========================================
// INTEGRACE FAKEMETA GRABU (ČISTÝ JEDI FORCE)
// ==========================================
public Cmd_GrabStart(id)
{
    if(!(get_user_flags(id) & ADMIN_FLAG_REQUIRED)) return PLUGIN_HANDLED;
    if(client_data[id][GRABBED] == 0) client_data[id][GRABBED] = -1;
    return PLUGIN_HANDLED;
}

public Cmd_GrabEnd(id)
{
    unset_grabbed(id);
    return PLUGIN_HANDLED;
}

public Cmd_PushStart(id) { client_data[id][FLAGS] |= CDF_IN_PUSH; return PLUGIN_HANDLED; }
public Cmd_PushEnd(id)   { client_data[id][FLAGS] &= ~CDF_IN_PUSH; return PLUGIN_HANDLED; }
public Cmd_PullStart(id) { client_data[id][FLAGS] |= CDF_IN_PULL; return PLUGIN_HANDLED; }
public Cmd_PullEnd(id)   { client_data[id][FLAGS] &= ~CDF_IN_PULL; return PLUGIN_HANDLED; }

public Cmd_Throw(id)
{
    new target = client_data[id][GRABBED];
    if(target > 0) {
        set_pev(target, pev_velocity, vel_by_aim(id, GRAB_THROW_FORCE));
        unset_grabbed(id);
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

public fm_player_prethink(id)
{
    if(!is_user_connected(id)) return FMRES_IGNORED;
    
    new target;
    if(client_data[id][GRABBED] == -1)
    {
        new Float:orig[3], Float:ret[3];
        get_view_pos(id, orig);
        ret = vel_by_aim(id, 9999);
        ret[0] += orig[0]; ret[1] += orig[1]; ret[2] += orig[2];
        
        target = traceline(orig, ret, id, ret);
        
        if(0 < target <= g_iMaxPlayers) {
            if(is_grabbed(target, id)) return FMRES_IGNORED;
            set_grabbed(id, target);
        }
    }
    
    target = client_data[id][GRABBED];
    if(target > 0)
    {
        if(!pev_valid(target) || (pev(target, pev_health) < 1 && pev(target, pev_max_health))) {
            unset_grabbed(id);
            return FMRES_IGNORED;
        }
        
        new cdf = client_data[id][FLAGS];
        if(cdf & CDF_IN_PULL) {
            new mindist = GRAB_MIN_DIST;
            new len = client_data[id][GRAB_LEN];
            if(len > mindist) {
                len -= GRAB_SPEED; if(len < mindist) len = mindist;
                client_data[id][GRAB_LEN] = len;
            }
        }
        else if(cdf & CDF_IN_PUSH) {
            if(client_data[id][GRAB_LEN] < 9999) client_data[id][GRAB_LEN] += GRAB_SPEED;
        }
        
        grab_think(id);
    }
    
    target = client_data[id][GRABBER];
    if(target > 0) grab_think(target);
    
    return FMRES_IGNORED;
}

public grab_think(id)
{
    new target = client_data[id][GRABBED];
    if(target <= 0 || !pev_valid(target)) return;
    
    if(pev(target, pev_movetype) == MOVETYPE_FLY && !(pev(target, pev_button) & IN_JUMP)) {
        client_cmd(target, "+jump;wait;-jump");
    }
    
    new Float:tmpvec[3], Float:tmpvec2[3], Float:torig[3], Float:tvel[3];
    get_view_pos(id, tmpvec);
    tmpvec2 = vel_by_aim(id, client_data[id][GRAB_LEN]);
    pev(target, pev_origin, torig);
    
    tvel[0] = ((tmpvec[0] + tmpvec2[0]) - torig[0]) * GRAB_FORCE;
    tvel[1] = ((tmpvec[1] + tmpvec2[1]) - torig[1]) * GRAB_FORCE;
    tvel[2] = ((tmpvec[2] + tmpvec2[2]) - torig[2]) * GRAB_FORCE;
    
    set_pev(target, pev_velocity, tvel);
}

public set_grabbed(id, target)
{
    // Pouze Červený Outer Glow (Svit okolo hráče)
    new Float:color[3] = {255.0, 0.0, 0.0};
    set_pev(target, pev_renderfx, kRenderFxGlowShell);
    set_pev(target, pev_rendercolor, color);
    set_pev(target, pev_rendermode, kRenderTransColor);
    set_pev(target, pev_renderamt, 150.0);
    
    if(0 < target <= g_iMaxPlayers) client_data[target][GRABBER] = id;
    
    client_data[id][FLAGS] = 0;
    client_data[id][GRABBED] = target;
    
    new Float:torig[3], Float:orig[3];
    pev(target, pev_origin, torig);
    pev(id, pev_origin, orig);
    
    client_data[id][GRAB_LEN] = floatround(get_distance_f(torig, orig));
    if(client_data[id][GRAB_LEN] < GRAB_MIN_DIST) client_data[id][GRAB_LEN] = GRAB_MIN_DIST;
}

public unset_grabbed(id)
{
    new target = client_data[id][GRABBED];
    if(target > 0 && pev_valid(target)) {
        new Float:color[3] = {255.0, 255.0, 255.0};
        set_pev(target, pev_renderfx, kRenderFxNone);
        set_pev(target, pev_rendercolor, color);
        set_pev(target, pev_rendermode, kRenderNormal);
        set_pev(target, pev_renderamt, 16.0);
        
        if(0 < target <= g_iMaxPlayers) client_data[target][GRABBER] = 0;
    }
    client_data[id][GRABBED] = 0;
}

public is_grabbed(target, grabber)
{
    for(new i = 1; i <= g_iMaxPlayers; i++) {
        if(client_data[i][GRABBED] == target) {
            client_print(grabber, print_chat, "[JB] Tohoto hrace jiz nekdo grabuje.");
            unset_grabbed(grabber);
            return true;
        }
    }
    return false;
}

public Event_DeathMsg() kill_grab(read_data(2));

public kill_grab(id)
{
    if(client_data[id][GRABBED]) unset_grabbed(id);
    else if(client_data[id][GRABBER]) unset_grabbed(client_data[id][GRABBER]);
}

// ==========================================
// POMOCNÉ SEKCE PRO GRAFICKÉ VÝPOČTY
// ==========================================
stock traceline(const Float:vStart[3], const Float:vEnd[3], const pIgnore, Float:vHitPos[3])
{
    engfunc(EngFunc_TraceLine, vStart, vEnd, 0, pIgnore, 0);
    get_tr2(0, TR_vecEndPos, vHitPos);
    return get_tr2(0, TR_pHit);
}

stock get_view_pos(const id, Float:vViewPos[3])
{
    new Float:vOfs[3];
    pev(id, pev_origin, vViewPos); pev(id, pev_view_ofs, vOfs);        
    vViewPos[0] += vOfs[0]; vViewPos[1] += vOfs[1]; vViewPos[2] += vOfs[2];
}

stock Float:vel_by_aim(id, speed = 1)
{
    new Float:v1[3], Float:vBlah[3];
    pev(id, pev_v_angle, v1);
    engfunc(EngFunc_AngleVectors, v1, v1, vBlah, vBlah);
    v1[0] *= speed; v1[1] *= speed; v1[2] *= speed;
    return v1;
}

// ==========================================
// AKCE MENU (PO KLIKNUTÍ NA HRÁČE Z LISTU)
// ==========================================
public Cmd_AdminActionMenu(id)
{
    new targetName[32], iTarget = g_iSelectedPlayer[id];
    if(is_user_connected(iTarget)) get_user_name(iTarget, targetName, charsmax(targetName));
    else copy(targetName, charsmax(targetName), "Neznamy hrac");

    new szMenu[512], iLen = 0;
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\d==== \rAkce s: \y%s \d====^n^n", targetName);
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r1. \y» \wPolozit otazku^n");
    
    new szTeam[16];
    if(g_iTargetTeam[id] == 0) copy(szTeam, charsmax(szTeam), "CT");
    else if(g_iTargetTeam[id] == 1) copy(szTeam, charsmax(szTeam), "T");
    else copy(szTeam, charsmax(szTeam), "SPECTATOR");
    
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r2. \y» \wVybrat team k presunu: \r[\y%s\r]^n", szTeam);
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r3. \y» \wPotvrdit presun hrace^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r4. \y» \wPotrestat hrace^n^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r9. \y» \yZavrit menu^n");
    
    show_menu(id, ACTION_MENU_KEYS, szMenu, -1, "AdminActionMenu");
}

public Handle_AdminActionMenu(id, key)
{
    switch(key)
    {
        case 0: Cmd_OtazkyMenu(id);
        case 1: { g_iTargetTeam[id] = (g_iTargetTeam[id] + 1) % 3; Cmd_AdminActionMenu(id); }
        case 2: {
            new iTarget = g_iSelectedPlayer[id];
            if(is_user_connected(iTarget)) {
                if(is_user_alive(iTarget)) silent_kill(iTarget);
                if(g_iTargetTeam[id] == 0) cs_set_user_team(iTarget, CS_TEAM_CT);
                else if(g_iTargetTeam[id] == 1) cs_set_user_team(iTarget, CS_TEAM_T);
                else cs_set_user_team(iTarget, CS_TEAM_SPECTATOR);
                client_print(id, print_chat, "[JB] Hrac byl uspesne presunut.");
            }
        }
        case 3: Cmd_PotrestatMenu(id);
    }
    return PLUGIN_HANDLED;
}

public Cmd_OtazkyMenu(id)
{
    new targetName[32];
    if(is_user_connected(g_iSelectedPlayer[id])) get_user_name(g_iSelectedPlayer[id], targetName, 31);
    else copy(targetName, 31, "Hrac");
    
    new szMenu[512], iLen = 0;
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\d==== \rPolozit otazku \d====^n^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r1. \y» \wSimon ma hlavni slovo^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r2. \y» \w[%s] \rNam rekne jestli ma mikrofon^n", targetName);
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r3. \y» \w[%s] \rNam vysvetli duvod zabiti^n", targetName);
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r4. \y» \w[%s] \rBude davat pozor na hru^n^n", targetName);
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r9. \y» \yZavrit menu^n");
    
    show_menu(id, OTAZKY_MENU_KEYS, szMenu, -1, "OtazkyMenu");
}

public Handle_OtazkyMenu(id, key)
{
    new targetName[32];
    if(is_user_connected(g_iSelectedPlayer[id])) get_user_name(g_iSelectedPlayer[id], targetName, 31);
    else copy(targetName, 31, "Hrac");

    new szMessage[128];
    switch(key)
    {
        case 0: copy(szMessage, charsmax(szMessage), "Simon ma hlavni slovo a nemluvi nikdo pokud nebyl vyvolan!");
        case 1: formatex(szMessage, charsmax(szMessage), "[%s] Nam rekne jake koliv slovo jestli ma mikrofon!", targetName);
        case 2: formatex(szMessage, charsmax(szMessage), "[%s] Nam vysvetli z jakeho duvodu hrace zabil!", targetName);
        case 3: formatex(szMessage, charsmax(szMessage), "[%s] Bude davat pozor na hru!", targetName);
        default: return PLUGIN_HANDLED;
    }
    set_hudmessage(255, 50, 50, -1.0, 0.35, 0, 0.0, 5.0, 0.1, 0.2);
    ShowSyncHudMsg(0, g_hudSyncOtazka, "%s", szMessage);
    return PLUGIN_HANDLED;
}

public Cmd_PotrestatMenu(id)
{
    new szMenu[512], iLen = 0;
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\d==== \rPotrestat hrace \d====^n^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r1. \y» \wBan k CT^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r2. \y» \wMute^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r3. \y» \wBan^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r4. \y» \wKick ze serveru^n");
    
    new szUnban[16];
    if(g_iUnbanType[id] == 0) copy(szUnban, 15, "Unban"); else copy(szUnban, 15, "Unmute");
    
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r5. \y» \wUnban / Unmute \r[ \y%s \r]^n", szUnban);
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r6. \y» \wProvest 5.^n^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu)-iLen, "\r9. \y» \yZavrit menu^n");
    
    show_menu(id, TREST_MENU_KEYS, szMenu, -1, "PotrestatMenu");
}

public Handle_PotrestatMenu(id, key)
{
    switch(key)
    {
        case 0, 1, 2: {
            g_iPunishType[id] = key + 1; client_cmd(id, "messagemode ZadejDelku");
            client_print(id, print_chat, "[JB] Zadej delku trestu! (Napr. 30, 2h, 5d)");
        }
        case 3: {
            g_iPunishType[id] = 4; copy(g_szPunishLength[id], 31, "Kick");
            client_cmd(id, "messagemode ZadejDuvod");
        }
        case 4: { g_iUnbanType[id] = 1 - g_iUnbanType[id]; Cmd_PotrestatMenu(id); }
        case 5: { g_iPunishType[id] = 5; client_cmd(id, "messagemode ZadejUnbanDuvod"); }
    }
    return PLUGIN_HANDLED;
}

public Cmd_ZadejDelku(id)
{
    new szArgs[32]; read_args(szArgs, charsmax(szArgs)); remove_quotes(szArgs); trim(szArgs);
    if(strlen(szArgs) == 0) return PLUGIN_HANDLED;
    copy(g_szPunishLength[id], 31, szArgs);
    client_cmd(id, "messagemode ZadejDuvod");
    return PLUGIN_HANDLED;
}

public Cmd_ZadejDuvod(id)
{
    new szReason[128]; read_args(szReason, charsmax(szReason)); remove_quotes(szReason);
    VyvolejTrest(id, szReason); return PLUGIN_HANDLED;
}

public Cmd_ZadejUnbanDuvod(id)
{
    new szReason[128]; read_args(szReason, charsmax(szReason)); remove_quotes(szReason);
    VyvolejTrest(id, szReason); return PLUGIN_HANDLED;
}

GetMinutes(const szTime[])
{
    new iLen = strlen(szTime); if(iLen == 0) return 0;
    new lastChar = szTime[iLen - 1];
    if(lastChar >= '0' && lastChar <= '9') return str_to_num(szTime);
    new szNum[32]; copy(szNum, iLen - 1, szTime);
    new iVal = str_to_num(szNum);
    switch(tolower(lastChar)) {
        case 'd': return iVal * 1440;
        case 'h': return iVal * 60;
        case 'm': return iVal;
    }
    return iVal;
}

public VyvolejTrest(id, const szReason[])
{
    new target = g_iSelectedPlayer[id]; if(!is_user_connected(target)) return;
    new targetName[32], adminName[32], typeStr[32];
    get_user_name(id, adminName, 31); get_user_name(target, targetName, 31);
    new userid = get_user_userid(target);
    new authid[32]; get_user_authid(target, authid, 31);
    new iMinutes = GetMinutes(g_szPunishLength[id]);

    switch(g_iPunishType[id]) {
        case 1: { copy(typeStr, 31, "Ban k CT"); server_cmd(CMD_CTBAN, userid, iMinutes, szReason); }
        case 2: { copy(typeStr, 31, "Mute"); server_cmd(CMD_GAG, userid, iMinutes, szReason); }
        case 3: {
            copy(typeStr, 31, "Ban");
            #if USE_AMXBANS == 1
                server_cmd(CMD_BAN_AMXBANS, iMinutes, authid, szReason);
            #else
                server_cmd(CMD_BAN_NORMAL, authid, iMinutes, szReason);
            #endif
        }
        case 4: { copy(typeStr, 31, "Kick"); server_cmd("amx_kick #%d ^"%s^"", userid, szReason); }
        case 5: {
            if(g_iUnbanType[id] == 0) { copy(typeStr, 31, "Zruseni Banu"); server_cmd("amx_unban ^"%s^"", authid); }
            else { copy(typeStr, 31, "Zruseni Mute"); server_cmd("amx_ungag #%d", userid); }
        }
    }
    set_hudmessage(100, 255, 100, 0.02, 0.40, 0, 0.0, 10.0, 0.1, 0.2);
    if(g_iPunishType[id] == 4 || g_iPunishType[id] == 5) ShowSyncHudMsg(0, g_hudSyncTrest, "[Hrac] %s^nDostal [%s]^nDuvod [%s]^nAdministratorem: [%s]", targetName, typeStr, szReason, adminName);
    else ShowSyncHudMsg(0, g_hudSyncTrest, "[Hrac] %s^nDostal [%s]^nNa Delku [%s]^nDuvod [%s]^nAdministratorem: [%s]", targetName, typeStr, g_szPunishLength[id], szReason, adminName);
}

// ==========================================
// SEZNAMY VÝBĚRU HRÁČŮ
// ==========================================
public BuildAdminPlayerList(id)
{
    g_iAdminPlayerCount[id] = 0;
    for(new i = 1; i <= g_iMaxPlayers; i++) {
        if(!is_user_connected(i)) continue;
        g_iAdminPlayers[id][g_iAdminPlayerCount[id]] = i; g_iAdminPlayerCount[id]++;
    }
    g_iAdminPage[id] = 0;
}

public Cmd_AdmintrestList(id)
{
    new szMenu[512], iLen = 0;
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d==== \rVyber hrace \d====^n^n");
    new iStart = g_iAdminPage[id] * 5, iEnd = iStart + 5;
    if(iEnd > g_iAdminPlayerCount[id]) iEnd = g_iAdminPlayerCount[id];
    
    for(new i = 0; i < 5; i++) {
        new iCurrentIndex = iStart + i;
        if(iCurrentIndex < iEnd) {
            new iPlayerID = g_iAdminPlayers[id][iCurrentIndex];
            new szName[32]; get_user_name(iPlayerID, szName, charsmax(szName));
            iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r%d. \y» \w%s^n", i + 1, szName);
        } else iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d%d. » Zadny hrac^n", i + 1);
    }
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n");
    new bool:bHasNext = (iEnd < g_iAdminPlayerCount[id]), bool:bHasPrev = (g_iAdminPage[id] > 0);
    
    if(bHasNext) iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r7. \y» \wDalsi strana^n");
    else iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d7. \y» Dalsi strana^n");
    if(bHasPrev) iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r8. \y» \wPredchozi Strana^n");
    else iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d8. \y» Predchozi Strana^n");
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r9. \y» \yZavrit menu^n");
    
    new iKeys = (1<<8); 
    if(iStart < iEnd) iKeys |= (1<<0); if(iStart + 1 < iEnd) iKeys |= (1<<1); if(iStart + 2 < iEnd) iKeys |= (1<<2);
    if(iStart + 3 < iEnd) iKeys |= (1<<3); if(iStart + 4 < iEnd) iKeys |= (1<<4);
    if(bHasNext) iKeys |= (1<<6); if(bHasPrev) iKeys |= (1<<7);
    show_menu(id, iKeys, szMenu, -1, "AdminTrestList");
}

public Handle_AdminTrestList(id, key)
{
    new iStart = g_iAdminPage[id] * 5;
    switch(key) {
        case 0, 1, 2, 3, 4: {
            new iSel = iStart + key;
            if(iSel < g_iAdminPlayerCount[id]) { g_iSelectedPlayer[id] = g_iAdminPlayers[id][iSel]; Cmd_AdminActionMenu(id); }
        }
        case 6: { g_iAdminPage[id]++; Cmd_AdmintrestList(id); }
        case 7: { g_iAdminPage[id]--; Cmd_AdmintrestList(id); }
    }
    return PLUGIN_HANDLED;
}