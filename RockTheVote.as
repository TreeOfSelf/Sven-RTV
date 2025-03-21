/*
Copyright (c) 2017 Drake "MrOats" Denston  
Edited & modified by Sebastian "TreeOfSelf" (2025)  

This Source Code Form is subject to the terms of the Mozilla Public  
License, v. 2.0. If a copy of the MPL was not distributed with this  
file, You can obtain one at http://mozilla.org/MPL/2.0/.  

Changes & Contributions:  
- Non-deterministic random
- Partial map nomination
- Option to instantly change map once all votes are cast
- Extend current map option

Documentation:  
https://github.com/TreeOfSelf/Sven-RTV 
*/

final class RTV_Data {
   private
    string m_szVotedMap = "";
   private
    string m_szNominatedMap = "";
   private
    bool m_bHasRTV = false;
   private
    CBasePlayer @m_pPlayer;
   private
    string m_szPlayerName;
   private
    string m_szSteamID = "";

    // RTV Data Properties

    string szVotedMap {
        get const { return m_szVotedMap; }
        set { m_szVotedMap = value; }
    }
    string szNominatedMap {
        get const { return m_szNominatedMap; }
        set { m_szNominatedMap = value; }
    }
    bool bHasRTV {
        get const { return m_bHasRTV; }
        set { m_bHasRTV = value; }
    }
    CBasePlayer @pPlayer {
        get const { return m_pPlayer; }
        set { @m_pPlayer = value; }
    }
    string szSteamID {
        get const { return m_szSteamID; }
        set { m_szSteamID = value; }
    }
    string szPlayerName {
        get const { return m_szPlayerName; }
        set { m_szPlayerName = value; }
    }

    // RTV Data Functions

    // Constructor

    RTV_Data(CBasePlayer @pPlr) {
        @pPlayer = pPlr;
        szSteamID = g_EngineFuncs.GetPlayerAuthId(pPlayer.edict());
        szPlayerName = pPlayer.pev.netname;
    }

}

final class PCG {
   private
    uint64 m_iseed;

    string seed {
        get const { return m_iseed; }
    }

    // PCG Functions

    uint nextInt(uint upper) {
        uint threshold = -upper % upper;

        while (true) {
            uint r = nextInt();

            if (r >= threshold) return r % upper;
        }

        return upper;
    }

    uint nextInt() {
        uint64 oldstate = m_iseed;
        m_iseed = oldstate * uint64(6364136223846793005) + uint(0);
        uint xorshifted = ((oldstate >> uint(18)) ^ oldstate) >> uint(27);
        uint rot = oldstate >> uint(59);
        return (xorshifted >> rot) | (xorshifted << ((-rot) & 31));
    }

    // PCG Constructors

    PCG(uint64 in_seed) { m_iseed = in_seed; }

    // Default Constructor
    PCG() { m_iseed = UnixTimestamp(); }

}

// ClientCommands

CClientCommand rtv("rtv", "Rock the Vote!", @RtvPush);
CClientCommand nominate("nominate", "Nominate a Map!", @NomPush);
CClientCommand forcevote("forcevote", "Lets admin force a vote", @ForceVote,
                         ConCommandFlag::AdminOnly);
CClientCommand addnominatemap(
    "addnominatemap", "Lets admin add as many nominatable maps as possible",
    @AddNominateMap, ConCommandFlag::AdminOnly);
CClientCommand removenominatemap(
    "removenominatemap", "Lets admin add as many nominatable maps as possible",
    @RemoveNominateMap, ConCommandFlag::AdminOnly);
CClientCommand cancelrtv("cancelrtv", "Lets admin cancel an ongoing RTV vote",
                         @CancelVote, ConCommandFlag::AdminOnly);

// Global Vars

CTextMenu @rtvmenu = null;
CTextMenu @nommenu = null;

array<RTV_Data @> rtv_plr_data;
array<string> forcenommaps;
array<string> prevmaps;
array<string> maplist;

PCG pcg_gen = PCG();

bool isVoting = false;
bool canRTV = false;

int secondsleftforvote = 0;

CCVar @g_SecondsUntilVote;
CCVar @g_MapList;
CCVar @g_ChangeOnAllVote;
CCVar @g_ExtendCurrentMap;
CCVar @g_WhenToChange;
CCVar @g_MaxMapsToVote;
CCVar @g_VotingPeriodTime;
CCVar @g_PercentageRequired;
CCVar @g_ChooseEnding;
CCVar @g_ExcludePrevMaps;

// Global Timers/Schedulers

CScheduledFunction @g_TimeToVote = null;
CScheduledFunction @g_TimeUntilVote = null;

// Hooks
void PluginInit() {
    g_Module.ScriptInfo.SetAuthor("Sebastian");
    g_Module.ScriptInfo.SetContactInfo(
        "https://github.com/TreeOfSelf/Sven-RTV");
    g_Hooks.RegisterHook(Hooks::Player::ClientDisconnect, @DisconnectCleanUp);
    g_Hooks.RegisterHook(Hooks::Player::ClientPutInServer, @AddPlayer);
    g_Hooks.RegisterHook(Hooks::Game::MapChange, @ResetVars);
    g_Hooks.RegisterHook(Hooks::Player::ClientSay, @Decider);

    @g_SecondsUntilVote =
        CCVar("secondsUntilVote", 0,
              "Delay before players can RTV after map has started",
              ConCommandFlag::AdminOnly);
    @g_MapList =
        CCVar("szMapListPath", "mapcycle.txt",
              "Path to list of maps to use. Defaulted to map cycle file",
              ConCommandFlag::AdminOnly);	  
    @g_ChangeOnAllVote =
        CCVar("changeOnAllVote", 1,
              "Whether to instantly change as soon as everyone has voted",
              ConCommandFlag::AdminOnly); 
    @g_ExtendCurrentMap =
        CCVar("extendCurrentMap", 1,
              "Whether to give the option to extend the current map",
              ConCommandFlag::AdminOnly); 
    @g_WhenToChange =
        CCVar("iChangeWhen", 0,
              "When to change maps post-vote: <0 for end of map, 0 for "
              "immediate change, >0 for seconds until change",
              ConCommandFlag::AdminOnly);
    @g_MaxMapsToVote = CCVar(
        "iMaxMaps", 8, "How many maps can players nominate and vote for later",
        ConCommandFlag::AdminOnly);
    @g_VotingPeriodTime =
        CCVar("secondsToVote", 25,
              "How long can players vote for a map before a map is chosen",
              ConCommandFlag::AdminOnly);
    @g_PercentageRequired =
        CCVar("iPercentReq", 51,
              "0-100, percent of players required to RTV before voting happens",
              ConCommandFlag::AdminOnly);
    @g_ChooseEnding =
        CCVar("iChooseEnding", 2,
              "Set to 1 to revote when a tie happens, 2 to choose randomly "
              "amongst the ties, 3 to await RTV again",
              ConCommandFlag::AdminOnly);
    @g_ExcludePrevMaps =
        CCVar("iExcludePrevMaps", 0,
              "How many maps to exclude from nomination or voting",
              ConCommandFlag::AdminOnly);
}


void MapActivate() {
    // Clean up Vars and Menus
    canRTV = false;
    isVoting = false;
    g_Scheduler.ClearTimerList();
    @g_TimeToVote = null;
    @g_TimeUntilVote = null;
    secondsleftforvote = g_VotingPeriodTime.GetInt();

    rtv_plr_data.resize(g_Engine.maxClients);
    for (uint i = 0; i < rtv_plr_data.length(); i++) @rtv_plr_data[i] = null;

    for (uint i = 0; i < forcenommaps.length(); i++) forcenommaps[i] = "";

    forcenommaps.resize(0);

    for (uint i = 0; i < maplist.length(); i++) maplist[i] = "";

    maplist.resize(0);

    if (@rtvmenu !is null) {
        rtvmenu.Unregister();
        @rtvmenu = null;
    }
    if (@nommenu !is null) {
        nommenu.Unregister();
        @nommenu = null;
    }

    maplist = GetMapList();
    /*
    for (size_t i = 0; i < prevmaps.length();)
    {

      if (maplist.find(prevmaps[i]) < 0)
        prevmaps.removeAt(i);
      else
        ++i;

    }
    */
    // int prevmaps_len = int(prevmaps.length());
    if (g_ExcludePrevMaps.GetInt() < 0) g_ExcludePrevMaps.SetInt(0);

    @g_TimeUntilVote = g_Scheduler.SetInterval("DecrementSeconds", 1,
                                               g_SecondsUntilVote.GetInt() + 1);
}

HookReturnCode Decider(SayParameters @pParams) {
    CBasePlayer @pPlayer = pParams.GetPlayer();
    const CCommand @pArguments = pParams.GetArguments();

    string firstArg = pArguments[0].ToLowercase();

    if (firstArg == "nominate" || firstArg == "!nominate") {
        NomPush(@pArguments, @pPlayer);
        return HOOK_HANDLED;

    } else if (firstArg == "rtv" || firstArg == "!rtv") {
        RtvPush(@pArguments, @pPlayer);
        return HOOK_HANDLED;

    } else
        return HOOK_CONTINUE;
}

HookReturnCode ResetVars(const string& in szNextMap) {
    g_Scheduler.ClearTimerList();
    @g_TimeToVote = null;
    @g_TimeUntilVote = null;

    prevmaps.insertLast(g_Engine.mapname);
    if ((int(prevmaps.length()) > g_ExcludePrevMaps.GetInt()))
        prevmaps.removeAt(0);

    return HOOK_HANDLED;
}

HookReturnCode DisconnectCleanUp(CBasePlayer @pPlayer) {
    RTV_Data @rtvdataobj = @rtv_plr_data[pPlayer.entindex() - 1];
    @rtvdataobj = null;

    return HOOK_HANDLED;
}

HookReturnCode AddPlayer(CBasePlayer @pPlayer) {
    RTV_Data @rtvdataobj = RTV_Data(pPlayer);
    @rtv_plr_data[pPlayer.entindex() - 1] = @rtvdataobj;

    return HOOK_HANDLED;
}

// Main Functions
bool HaveAllPlayersVoted() {
    int totalPlayers = 0;
    int totalVoted = 0;

    for (int i = 1; i <= g_Engine.maxClients; i++) {
        CBasePlayer @pPlayer = g_PlayerFuncs.FindPlayerByIndex(i);
        if (pPlayer !is null && pPlayer.IsConnected()) {
            totalPlayers++;

            RTV_Data @rtvdataobj = @rtv_plr_data[pPlayer.entindex() - 1];
            if (@rtvdataobj !is null && !rtvdataobj.szVotedMap.IsEmpty()) {
                totalVoted++;
            }
        }
    }

    return totalPlayers > 0 && totalPlayers == totalVoted;
}

void DecrementSeconds() {
    if (g_SecondsUntilVote.GetInt() == 0) {
        canRTV = true;
        g_Scheduler.RemoveTimer(g_TimeUntilVote);
        @g_TimeUntilVote = null;

    } else {
        g_SecondsUntilVote.SetInt(g_SecondsUntilVote.GetInt() - 1);
    }
}

void DecrementVoteSeconds() {
    if (g_ChangeOnAllVote.GetInt() == 1 && HaveAllPlayersVoted()) {
        PostVote();
        g_Scheduler.RemoveTimer(g_TimeUntilVote);
        @g_TimeUntilVote = null;
        secondsleftforvote = g_VotingPeriodTime.GetInt();
        return;
    }

    if (secondsleftforvote == g_VotingPeriodTime.GetInt()) {
        CBasePlayer @pPlayer = PickRandomPlayer();
        string msg = string(secondsleftforvote) + " seconds left to vote.";
        g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
        secondsleftforvote--;
    } else if (secondsleftforvote == 10) {
        CBasePlayer @pPlayer = PickRandomPlayer();

        string msg = string(secondsleftforvote) + " seconds left to vote.";
        g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
        secondsleftforvote--;
    } else if (secondsleftforvote == 5) {
        CBasePlayer @pPlayer = PickRandomPlayer();
        string msg = string(secondsleftforvote) + " seconds left to vote.";
        g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
        secondsleftforvote--;
    } else if (secondsleftforvote == 4) {
        CBasePlayer @pPlayer = PickRandomPlayer();
        string msg = string(secondsleftforvote) + " seconds left to vote.";
        g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
        secondsleftforvote--;
    } else if (secondsleftforvote == 3) {
        CBasePlayer @pPlayer = PickRandomPlayer();

        string msg = string(secondsleftforvote) + " seconds left to vote.";
        g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
        secondsleftforvote--;
    } else if (secondsleftforvote == 2) {
        CBasePlayer @pPlayer = PickRandomPlayer();

        string msg = string(secondsleftforvote) + " seconds left to vote.";
        g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
        secondsleftforvote--;
    } else if (secondsleftforvote == 1) {
        CBasePlayer @pPlayer = PickRandomPlayer();

        string msg = string(secondsleftforvote) + " seconds left to vote.";
        g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
        secondsleftforvote--;
    } else if (secondsleftforvote == 0) {
        PostVote();
        g_Scheduler.RemoveTimer(g_TimeUntilVote);
        @g_TimeUntilVote = null;
        secondsleftforvote = g_VotingPeriodTime.GetInt();
    } else {
        string msg = string(secondsleftforvote) + " seconds left to vote.";
        g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
        secondsleftforvote--;
    }
}

void RtvPush(const CCommand @pArguments, CBasePlayer @pPlayer) {
    if (isVoting) {
        rtvmenu.Open(0, 0, pPlayer);

    } else {
        if (canRTV) {
            RockTheVote(pPlayer);

        } else {
            MessageWarnAllPlayers(pPlayer, "RTV will enable in " +
                                               g_SecondsUntilVote.GetInt() +
                                               " seconds.");
        }
    }
}

void RtvPush(const CCommand @pArguments) {
    CBasePlayer @pPlayer = g_ConCommandSystem.GetCurrentPlayer();

    if (isVoting) {
        rtvmenu.Open(0, 0, pPlayer);

    } else {
        if (canRTV) {
            RockTheVote(pPlayer);

        } else {
            MessageWarnAllPlayers(pPlayer, "RTV will enable in " +
                                               g_SecondsUntilVote.GetInt() +
                                               " seconds.");
        }
    }
}

void NomPush(const CCommand @pArguments, CBasePlayer @pPlayer) {
    if (pArguments.ArgC() == 2) {
        SearchNominateMap(pPlayer, pArguments.Arg(1));

    } else if (pArguments.ArgC() == 1) {
        NominateMenu(pPlayer);
    }
}

void NomPush(const CCommand @pArguments) {
    CBasePlayer @pPlayer = g_ConCommandSystem.GetCurrentPlayer();

    if (pArguments.ArgC() == 2) {
        NominateMap(pPlayer, pArguments.Arg(1));

    } else if (pArguments.ArgC() == 1) {
        NominateMenu(pPlayer);
    }
}

void ForceVote(const CCommand @pArguments, CBasePlayer @pPlayer) {
    if (pArguments.ArgC() >= 2) {
        array<string> rtvList;

        for (int i = 1; i < pArguments.ArgC(); i++) {
            if (g_EngineFuncs.IsMapValid(pArguments.Arg(i)))
                rtvList.insertLast(pArguments.Arg(i));
            else
                MessageWarnPlayer(
                    pPlayer,
                    pArguments.Arg(i) + " is not a valid map. Skipping...");
        }

        VoteMenu(rtvList);
        @g_TimeToVote = g_Scheduler.SetInterval(
            "DecrementVoteSeconds", 1, g_VotingPeriodTime.GetInt() + 1);

    } else if (pArguments.ArgC() == 1) {
        BeginVote();
        @g_TimeToVote = g_Scheduler.SetInterval(
            "DecrementVoteSeconds", 1, g_VotingPeriodTime.GetInt() + 1);
    }
}

void ForceVote(const CCommand @pArguments) {
    CBasePlayer @pPlayer = g_ConCommandSystem.GetCurrentPlayer();

    if (pArguments.ArgC() >= 2) {
        array<string> rtvList;

        for (int i = 1; i < pArguments.ArgC(); i++) {
            if (g_EngineFuncs.IsMapValid(pArguments.Arg(i)))
                rtvList.insertLast(pArguments.Arg(i));
            else
                MessageWarnPlayer(
                    pPlayer,
                    pArguments.Arg(i) + " is not a valid map. Skipping...");
        }

        VoteMenu(rtvList);
        @g_TimeToVote = g_Scheduler.SetInterval(
            "DecrementVoteSeconds", 1, g_VotingPeriodTime.GetInt() + 1);

    } else if (pArguments.ArgC() == 1) {
        BeginVote();
        @g_TimeToVote = g_Scheduler.SetInterval(
            "DecrementVoteSeconds", 1, g_VotingPeriodTime.GetInt() + 1);
    }
}

void AddNominateMap(const CCommand @pArguments) {
    CBasePlayer @pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    array<string> plrnom = GetNominatedMaps();

    if (pArguments.ArgC() == 1) {
        MessageWarnPlayer(pPlayer,
                          "You did not specify a map to nominate. Try again.");
        return;
    }

    if (g_EngineFuncs.IsMapValid(pArguments.Arg(1))) {
        if ((plrnom.find(pArguments.Arg(1)) < 0) &&
            (forcenommaps.find(pArguments.Arg(1)) < 0)) {
            forcenommaps.insertLast(pArguments.Arg(1));
            MessageWarnPlayer(pPlayer,
                              "Map was added to force nominated maps list");

        } else
            MessageWarnPlayer(
                pPlayer,
                "Map was already nominated by someone else. Skipping...");

    } else
        MessageWarnPlayer(pPlayer, "Map does not exist. Skipping...");
}

void RemoveNominateMap(const CCommand @pArguments) {
    CBasePlayer @pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    array<string> plrnom = GetNominatedMaps();

    if (pArguments.ArgC() == 1) {
        MessageWarnPlayer(
            pPlayer,
            "You did not specify a map to remove from nominations. Try again.");
        return;
    }

    if (plrnom.find(pArguments.Arg(1)) >= 0) {
        // Let's figure out who nominated that map and remove it...
        for (uint i = 0; i < rtv_plr_data.length(); i++) {
            if (@rtv_plr_data[i] !is null) {
                if (rtv_plr_data[i].szNominatedMap == pArguments.Arg(1)) {
                    MessageWarnAllPlayers(
                        pPlayer,
                        string(rtv_plr_data[i].szPlayerName + " has removed " +
                               rtv_plr_data[i].szPlayerName +
                               " nomination of " +
                               rtv_plr_data[i].szNominatedMap));
                    rtv_plr_data[i].szNominatedMap = "";
                }
            }
        }

    } else if (forcenommaps.find(pArguments.Arg(1)) >= 0) {
        forcenommaps.removeAt(forcenommaps.find(pArguments.Arg(1)));
        MessageWarnPlayer(pPlayer, pArguments.Arg(1) +
                                       " was removed from admin's nominations");

    } else
        MessageWarnPlayer(
            pPlayer, pArguments.Arg(1) + " was not nominated. Skipping...");
}

void CancelVote(const CCommand @pArguments) {
    CBasePlayer @pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    RTV_Data @rtvdataobj = @rtv_plr_data[pPlayer.entindex() - 1];

    g_Scheduler.RemoveTimer(@g_TimeToVote);
    CScheduledFunction @g_TimeToVote = null;

    ClearRTV();

    MessageWarnAllPlayers(pPlayer, "The vote has been cancelled by " +
                                       string(rtvdataobj.szPlayerName));
}

CBasePlayer @PickRandomPlayer() {
    CBasePlayer @pPlayer;
    for (int i = 1; i <= g_Engine.maxClients; i++) {
        @pPlayer = g_PlayerFuncs.FindPlayerByIndex(i);
        if ((pPlayer !is null) && (pPlayer.IsConnected())) break;
    }

    return @pPlayer;
}

void MessageWarnPlayer(CBasePlayer @pPlayer, string msg) {
    g_PlayerFuncs.SayText(pPlayer, "[RTV] " + msg + "\n");
}

void MessageWarnAllPlayers(CBasePlayer @pPlayer, string msg) {
    g_PlayerFuncs.SayTextAll(pPlayer, "[RTV] " + msg + "\n");
}

void SearchNominateMap(CBasePlayer @pPlayer, string szMapName) {
    array<string> mapList = maplist;
    array<string> mapsFound;

    // Convert the input map name to lowercase
    szMapName.ToLowercase();

	
	for (uint i = 0; i < mapList.length(); i++) {
		string mapNameLower = mapList[i];
		mapNameLower.ToLowercase();
		if (mapNameLower.Find(szMapName) != String::INVALID_INDEX) {
			mapsFound.insertLast(mapList[i]);
		}
	}
    
	 // If only found one map
	 if (mapsFound.length() == 1) {
        NominateMap(pPlayer, mapsFound[0]);
        return;
    }
	
    @nommenu = CTextMenu(@nominate_MenuCallback);
    nommenu.SetTitle("Nominate...");

    array<string> nomList = mapsFound;
    nomList.sortAsc();

    for (uint i = 0; i < nomList.length(); i++)
        nommenu.AddItem(nomList[i], any(nomList[i]));

    if (!(nommenu.IsRegistered())) nommenu.Register();

    nommenu.Open(0, 0, pPlayer);
}

void NominateMap(CBasePlayer @pPlayer, string szMapName) {
    RTV_Data @rtvdataobj = @rtv_plr_data[pPlayer.entindex() - 1];
    array<string> mapsNominated = GetNominatedMaps();
    array<string> mapList = maplist;

    if (mapList.find(szMapName) < 0) {
        MessageWarnPlayer(pPlayer, "Map does not exist.");
        return;
    }

    if (prevmaps.find(szMapName) >= 0) {
        MessageWarnPlayer(
            pPlayer,
            "Map has already been played and will be excluded until later.");
        return;
    }

    if (forcenommaps.find(szMapName) >= 0) {
        MessageWarnPlayer(
            pPlayer, "\"" + szMapName +
                         "\" was found in the admin's list of nominated maps.");
        return;
    }

    if (mapsNominated.find(szMapName) >= 0) {
        MessageWarnPlayer(pPlayer,
                          "Someone nominated \"" + szMapName + "\" already.");
        return;
    }

    if (int(mapsNominated.length()) > g_MaxMapsToVote.GetInt()) {
        MessageWarnPlayer(pPlayer,
                          "Players have reached maxed number of nominations!");
        return;
    }

    if (rtvdataobj.szNominatedMap.IsEmpty()) {
        MessageWarnAllPlayers(
            pPlayer,
            rtvdataobj.szPlayerName + " has nominated \"" + szMapName + "\".");
        rtvdataobj.szNominatedMap = szMapName;
        return;

    } else {
        MessageWarnAllPlayers(
            pPlayer, rtvdataobj.szPlayerName +
                         " has changed their nomination to \"" + szMapName +
                         "\". ");
        rtvdataobj.szNominatedMap = szMapName;
        return;
    }
}

void nominate_MenuCallback(CTextMenu @nommenu, CBasePlayer @pPlayer, int page,
                           const CTextMenuItem @item) {
    if (item !is null && pPlayer !is null) NominateMap(pPlayer, item.m_szName);

    if (@nommenu !is null && nommenu.IsRegistered()) {
        nommenu.Unregister();
        @nommenu = null;
    }
}

void NominateMenu(CBasePlayer @pPlayer) {
    @nommenu = CTextMenu(@nominate_MenuCallback);
    nommenu.SetTitle("Nominate...");

    array<string> mapList = maplist;

    // Remove any maps found in the previous map exclusion list or force
    // nominated maps
    for (uint i = 0; i < mapList.length();) {
        if ((prevmaps.find(mapList[i]) >= 0))
            mapList.removeAt(i);
        else if ((forcenommaps.find(mapList[i]) >= 0))
            mapList.removeAt(i);
        else
            ++i;
    }

    mapList.sortAsc();

    for (uint i = 0; i < mapList.length(); i++)
        nommenu.AddItem(mapList[i], any(mapList[i]));

    if (!(nommenu.IsRegistered())) nommenu.Register();

    nommenu.Open(0, 0, pPlayer);
}

void RockTheVote(CBasePlayer @pPlayer) {
    RTV_Data @rtvdataobj = @rtv_plr_data[pPlayer.entindex() - 1];
    int rtvRequired = CalculateRequired();

    if (rtvdataobj.bHasRTV) {
        MessageWarnPlayer(pPlayer, "You have already Rocked the Vote!");
        MessageWarnAllPlayers(pPlayer, "" + GetRTVd() + " of " + rtvRequired +
                                           " players until vote initiates!");

    } else {
        rtvdataobj.bHasRTV = true;
        MessageWarnPlayer(pPlayer, "You have Rocked the Vote!");
        MessageWarnAllPlayers(pPlayer, "" + GetRTVd() + " of " + rtvRequired +
                                           " players until vote initiates!");
    }

    if (GetRTVd() >= rtvRequired) {
        if (!isVoting) {
            isVoting = true;
            BeginVote();
        }

        @g_TimeToVote = g_Scheduler.SetInterval(
            "DecrementVoteSeconds", 1, g_VotingPeriodTime.GetInt() + 1);
    }
}

void rtv_MenuCallback(CTextMenu @rtvmenu, CBasePlayer @pPlayer, int page,
                      const CTextMenuItem @item) {
    if (item !is null && pPlayer !is null) vote(item.m_szName, pPlayer);
}

void VoteMenu(array<string> rtvList) {
    canRTV = true;
    MessageWarnAllPlayers(
        PickRandomPlayer(),
        "You have " + g_VotingPeriodTime.GetInt() + " seconds to vote!");

    @rtvmenu = CTextMenu(@rtv_MenuCallback);
    rtvmenu.SetTitle("RTV Vote");
    for (uint i = 0; i < rtvList.length(); i++) {
        rtvmenu.AddItem(rtvList[i], any(rtvList[i]));
    }

    if (!(rtvmenu.IsRegistered())) {
        rtvmenu.Register();
    }

    for (int i = 1; i <= g_Engine.maxClients; i++) {
        CBasePlayer @pPlayer = g_PlayerFuncs.FindPlayerByIndex(i);

        if (pPlayer !is null) {
            rtvmenu.Open(0, 0, pPlayer);
        }
    }
}

void vote(string votedMap, CBasePlayer @pPlayer) {
    RTV_Data @rtvdataobj = @rtv_plr_data[pPlayer.entindex() - 1];

    if (rtvdataobj.szVotedMap.IsEmpty()) {
        rtvdataobj.szVotedMap = votedMap;
        MessageWarnPlayer(pPlayer, "You voted for " + votedMap);

    } else {
        rtvdataobj.szVotedMap = votedMap;
        MessageWarnPlayer(pPlayer, "You changed your vote to " + votedMap);
    }
}

void BeginVote() {
    canRTV = true;

    array<string> rtvList;
    array<string> mapsNominated = GetNominatedMaps();

    for (uint i = 0; i < forcenommaps.length(); i++)
        rtvList.insertLast(forcenommaps[i]);

    for (uint i = 0; i < mapsNominated.length(); i++)
        rtvList.insertLast(mapsNominated[i]);

    // Determine how many more maps need to be added to menu
    int remaining = 0;
    if (int(maplist.length()) < g_MaxMapsToVote.GetInt()) {
        // maplist is smaller, use it
        remaining = int(maplist.length() - rtvList.length());

    } else if (int(maplist.length()) > g_MaxMapsToVote.GetInt()) {
        // MaxMaps is smaller, use it
        remaining = g_MaxMapsToVote.GetInt() - int(rtvList.length());

    } else if (int(maplist.length()) == g_MaxMapsToVote.GetInt()) {
        // They are same length, use maplist
        remaining = int(maplist.length() - rtvList.length());
    }

    while (remaining > 0) {
        // Fill rest of menu with random maps
        string rMap = RandomMap();

        if (((rtvList.find(rMap)) < 0) && (prevmaps.find(rMap) < 0)) {
            rtvList.insertLast(rMap);
            remaining--;
        }
    }

	if (g_ExtendCurrentMap.GetInt() == 1) {
		rtvList.insertLast("Extend current map");
	}

    // Give Menus to Vote!
    VoteMenu(rtvList);
}

void PostVote() {
    array<string> rtvList = GetVotedMaps();
    dictionary rtvVotes;
    int highestVotes = 0;

    // Initialize Dictionary of votes
    for (uint i = 0; i < rtvList.length(); i++) {
        rtvVotes.set(rtvList[i], 0);
    }

    for (uint i = 0; i < rtvList.length(); i++) {
        int val = int(rtvVotes[rtvList[i]]);
        rtvVotes[rtvList[i]] = val + 1;
    }

    // Find highest amount of votes
    for (uint i = 0; i < rtvList.length(); i++) {
        if (int(rtvVotes[rtvList[i]]) >= highestVotes) {
            highestVotes = int(rtvVotes[rtvList[i]]);
        }
    }

    // Nobody voted?
    if (highestVotes == 0) {
        string chosenMap = RandomMap();
        MessageWarnAllPlayers(
            PickRandomPlayer(),
            "\"" + chosenMap +
                "\" has been randomly chosen since nobody picked");
        ChooseMap(chosenMap, false);
        return;
    }

    // Find how many maps were voted at the highest
    array<string> candidates;
    array<string> singlecount = rtvVotes.getKeys();
    for (uint i = 0; i < singlecount.length(); i++) {
        if (int(rtvVotes[singlecount[i]]) == highestVotes) {
            candidates.insertLast(singlecount[i]);
        }
    }
    singlecount.resize(0);

    // Revote or random choose if more than one map is at highest vote count
    if (candidates.length() > 1) {
        if (g_ChooseEnding.GetInt() == 1) {
            ClearVotedMaps();
            MessageWarnAllPlayers(PickRandomPlayer(),
                                  "There was a tie! Revoting...");
            @g_TimeToVote = g_Scheduler.SetInterval(
                "DecrementVoteSeconds", 1, g_VotingPeriodTime.GetInt() + 1);
            VoteMenu(candidates);
            return;

        } else if (g_ChooseEnding.GetInt() == 2) {
            string chosenMap = RandomMap(candidates);
            MessageWarnAllPlayers(
                PickRandomPlayer(),
                "\"" + chosenMap +
                    "\" has been randomly chosen amongst the tied");
            ChooseMap(chosenMap, false);
            return;

        } else if (g_ChooseEnding.GetInt() == 3) {
            ClearVotedMaps();
            ClearRTV();

            MessageWarnAllPlayers(PickRandomPlayer(),
                                  "There was a tie! Please RTV again...");

        } else
            g_Log.PrintF("[RTV] Fix your ChooseEnding CVar!\n");
    } else {
        MessageWarnAllPlayers(PickRandomPlayer(),
                              "\"" + candidates[0] + "\" has been chosen!");
        ChooseMap(candidates[0], false);
        return;
    }
}

void ChooseMap(string chosenMap, bool forcechange) {
    if (chosenMap == "Extend current map") {
        isVoting = false;
        g_Scheduler.RemoveTimer(@g_TimeToVote);
        CScheduledFunction @g_TimeToVote = null;

        ClearRTV();

        rtv_plr_data.resize(g_Engine.maxClients);
        for (uint i = 0; i < rtv_plr_data.length(); i++) {
            if (@rtv_plr_data[i] != null) {
                RTV_Data @rtvdataobj = @rtv_plr_data[i];
                rtvdataobj.szVotedMap = "";
                rtvdataobj.szNominatedMap = "";
                rtvdataobj.bHasRTV = false;
            }
        }

        for (uint i = 0; i < forcenommaps.length(); i++) forcenommaps[i] = "";

        forcenommaps.resize(0);

        for (uint i = 0; i < maplist.length(); i++) maplist[i] = "";

        maplist.resize(0);

        if (@rtvmenu !is null) {
            rtvmenu.Unregister();
            @rtvmenu = null;
        }
        if (@nommenu !is null) {
            nommenu.Unregister();
            @nommenu = null;
        }

        maplist = GetMapList();

        if (g_ExcludePrevMaps.GetInt() < 0) g_ExcludePrevMaps.SetInt(0);

        return;
    }

    // After X seconds passed or if CVar WhenToChange is 0
    if (forcechange || (g_WhenToChange.GetInt() == 0)) {
        g_Log.PrintF("[RTV] Changing map to \"%1\"\n", chosenMap);
        g_EngineFuncs.ServerCommand("changelevel " + chosenMap + "\n");
    }
    // Change after X Seconds
    if (g_WhenToChange.GetInt() > 0) {
        g_Scheduler.SetTimeout("ChooseMap", g_WhenToChange.GetInt(), chosenMap,
                               true);
    }
    // Change after map end
    if (g_WhenToChange.GetInt() < 0) {
        // Handle "infinite time left" maps by setting time left to X minutes
        if (g_EngineFuncs.CVarGetFloat("mp_timelimit") == 0) {
            // Can't set mp_timeleft...
            // g_EngineFuncs.CVarSetFloat("mp_timeleft", 600);
            g_Scheduler.SetTimeout("ChooseMap", abs(g_WhenToChange.GetInt()),
                                   chosenMap, true);
        }

        g_EngineFuncs.ServerCommand("mp_nextmap " + chosenMap + "\n");
        g_EngineFuncs.ServerCommand("mp_nextmap_cycle " + chosenMap + "\n");
        MessageWarnAllPlayers(
            PickRandomPlayer(),
            "Next map has been set to \"" + chosenMap + "\".");
    }
}

// Utility Functions

int CalculateRequired() {
    return int(ceil(g_PlayerFuncs.GetNumPlayers() *
                    (g_PercentageRequired.GetInt() / 100.0f)));
}

string RandomMap() { return maplist[Math.RandomLong(0, maplist.length())]; }

string RandomMap(array<string> mapList) {
    return mapList[Math.RandomLong(0, mapList.length())];
}

string RandomMap(array<string> mapList, uint length) {
    return mapList[Math.RandomLong(0, length)];
}

array<string> GetNominatedMaps() {
    array<string> nommaps;

    for (uint i = 0; i < rtv_plr_data.length(); i++) {
        RTV_Data @pPlayer = @rtv_plr_data[i];

        if (pPlayer !is null)
            if (!(pPlayer.szNominatedMap.IsEmpty()))
                nommaps.insertLast(pPlayer.szNominatedMap);
    }

    return nommaps;
}

array<string> GetMapList() {
    array<string> mapList;

    if (!(g_MapList.GetString() == "mapcycle.txt")) {
        File @file =
            g_FileSystem.OpenFile(g_MapList.GetString(), OpenFile::READ);

        if (file !is null && file.IsOpen()) {
            g_Game.AlertMessage(at_console, "[RTV] Opening file!!!\n");
            while (!file.EOFReached()) {
                string sLine;
                file.ReadLine(sLine);

                if (sLine.SubString(0, 1) == "#" || sLine.IsEmpty()) continue;

                sLine.Trim();

                mapList.insertLast(sLine);
            }

            file.Close();

            for (uint i = 0; i < mapList.length();) {
                if (!(g_EngineFuncs.IsMapValid(mapList[i]))) {
                    mapList.removeAt(i);

                } else
                    ++i;
            }
        }

        return mapList;
    }

    g_Game.AlertMessage(at_console, "[RTV] Using MapCycle.txt\n");
    return g_MapCycle.GetMapCycle();
}

array<string> GetVotedMaps() {
    array<string> votedmaps;

    for (uint i = 0; i < rtv_plr_data.length(); i++) {
        if (@rtv_plr_data[i] !is null)
            if (!(rtv_plr_data[i].szVotedMap.IsEmpty()))
                votedmaps.insertLast(rtv_plr_data[i].szVotedMap);
    }

    return votedmaps;
}

int GetRTVd() {
    int counter = 0;
    for (uint i = 0; i < rtv_plr_data.length(); i++) {
        if (@rtv_plr_data[i] !is null)
            if (rtv_plr_data[i].bHasRTV) counter += 1;
    }

    return counter;
}

void ClearVotedMaps() {
    for (uint i = 0; i < rtv_plr_data.length(); i++) {
        if (@rtv_plr_data[i] !is null) {
            rtv_plr_data[i].szVotedMap = "";
        }
    }
}

void ClearRTV() {
    for (uint i = 0; i < rtv_plr_data.length(); i++) {
        if (@rtv_plr_data[i] !is null) {
            rtv_plr_data[i].bHasRTV = false;
        }
	}
}
