# RockTheVote.as

## Information about RockTheVote.as   
First Created: November 27th, 2016   
Last Updated: February 10th, 2025   
Current Status: Stable, might contain bugs.   
Works with the v5.26 Build of Sven Co-Op.    

Original plugin authored by [MrOats](https://github.com/MrOats/AngelScript_SC_Plugins)

Changes & Contributions in this Version:  
- Non-deterministic random
- Partial map nomination
- Option to add "Extent current map" to RTV menu
- Option to instantly change map once all votes are cast


Download Link of the Last Stable version of Plugin
Installation Instructions
Copy 'RockTheVote.as' to 'svencoop\scripts\plugins'. And add this to 'default_plugins.txt':

```
    "plugin"
    {
        "name" "RockTheVote"
        "script" "RockTheVote"
        "concommandns" "rtv"
    }
```

Add this to 'server.cfg'

```
// RTV Plugin Global Configuration
as_command rtv.secondsUntilVote 120
as_command rtv.szMapListPath "mapcycle.txt"
as_command rtv.iChangeWhen 0
as_command rtv.iMaxMaps 9
as_command rtv.secondsToVote 25
as_command rtv.iPercentReq 66
as_command rtv.changeOnAllVote 1
as_command rtv.extendCurrentMap 1
as_command rtv.iChooseEnding 1
as_command rtv.iExcludePrevMaps 0
as_command rtv.bPlaySounds 1
```

## Documentation
A nomination-based vote system that allows players to vote on a new map to play on. Typically players will nominate a map, then issue the RTV command until enough players have committed the RTV command. Once enough players say RTV, then voting begins. Voting will restart if there are ties with the maps that have tied.

## Console Commands:
- `.rtv` - Adds a vote to change maps until enough players have voted.
- `.nominate [map name]` - If a map isn't specified, a menu will display for the player to pick a map to nominate. One map per player, until MaxMapsToVote.
- `.addnominatemap [map name]` - Lets an admin add a map to the list of forced nominations. List can be as big as they prefer.
- `.removenominatemap [map name]` - Lets an admin remove a map from players' nominations or the forced nominations list.
- `.forcevote [list of map names separated by spaces]` - Lets an admin force a map vote. If list of maps aren't given, then it will just start a regular vote based on nominations.
- `.cancelrtv` - Lets an admin cancel an ongoing vote. Will clear RTVs, so players have to type RTV again.

## Chat Commands:
- `rtv` - Adds a vote to change maps until enough players added
- `nominate [map name / partial map name]` - If a map isn't specicif to one map, a menu will display for the player to pick a map to nominate. One map per player, until MaxMapsToVote.
  
## Configs:
There are multiple configurations you can manipulate, you have to go to console and type as_command rtv.cvarhere value.
Add the below defaults to your "server.cfg" file if you haven't already.


You can use a .cfg file to give a map unique settings for the plugin.
Just navigate to the folder of the map, and find/create a file named mapname.cfg and put lines with `as_command rtv.cvarhere value`


Adjust values above as needed. If a .cfg file is not found for the map, then it will assume the values you put in server.cfg

## CVar Help:

```
secondsUntilVote - (0 - N) Delay in seconds before players can RTV after map has started
szMapListPath - Path to the list of maps you want to use. Place list under a folder inside svencoop/scripts/plugins, and change this CVar to "scripts/plugins/myfolder/mylist.txt", where myfolder is the folder your made, and mylist.txt being any file.
iChangeWhen - When to change maps post-vote: <0 for end of map, 0 for immediate change, >0 for seconds until change. If using <0, put a number for the amount of seconds until change in case the map has an infinite time left.
iMaxMaps - (1 - However many maps in your list, please be careful to adhere to the amount of maps in your list) Decides how many maps can be nominated and voted for later.
secondsToVote - (1 - N) How long can players vote for a map before a map is chosen
iPercentReq - (1-100), percent of players required to RTV before voting happens
changeOnAllVote - (1 (True) or 0 (False)), whether or not to instantly change the map once all players have casted their votes
extendCurrentMap - (1 (True) or 0 (False)), whether to give the option to extend the current map
iChooseEnding - (1, 2, 3) Set to 1 to revote when a tie happens, 2 to choose randomly amongst the ties, 3 to await RTV again
iExcludePrevMaps - (0-N) How many previously played maps to exclude from voting? Deletes the first one in list when it reaches configured amount.
rtv.bPlaySounds - (1 (True) or 0 (False)) Allow sounds to be played when RTV begins the voting process.
```

## Support

[Support discord here!]( https://discord.gg/3tP3Tqu983)

## License

[MPL v2.0](https://creativecommons.org/public-domain/cc0/](http://mozilla.org/MPL/2.0/)

