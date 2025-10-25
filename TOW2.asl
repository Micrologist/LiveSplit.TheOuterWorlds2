state("TheOuterWorlds2-Win64-Shipping"){}

startup
{
    vars.Log = (Action<object>)((output) => print("[The Outer Worlds 2 ASL] " + output));

    vars.SetTextComponent = (Action<string,string>)((id,text)=>{
        var lsUI = typeof(LiveSplit.UI.Components.LayoutComponent).Namespace;
        var txtTypeName = "LiveSplit.UI.Components.TextComponent";
        var asm = "LiveSplit.Text.dll";
        var layout = timer.Layout;

        var tComps = layout.Components
            .Where(c => c.GetType().Name=="TextComponent")
            .Select(c => c.GetType().GetProperty("Settings").GetValue(c,null));

        var s = tComps.FirstOrDefault(o => (string)o.GetType().GetProperty("Text1").GetValue(o,null)==id);

        if(s==null){
            var tAsm = Assembly.LoadFrom("Components\\"+asm);
            var comp = Activator.CreateInstance(tAsm.GetType(txtTypeName),timer);
            layout.LayoutComponents.Add(new LiveSplit.UI.Components.LayoutComponent(asm,(LiveSplit.UI.Components.IComponent)comp));
            s = comp.GetType().GetProperty("Settings").GetValue(comp,null);
            s.GetType().GetProperty("Text1").SetValue(s,id);
        }

        s.GetType().GetProperty("Text2").SetValue(s,text);
    });

    timer.CurrentTimingMethod = TimingMethod.GameTime;

    settings.Add("speedometer", false, "Show speed readout");
    settings.Add("debugText", false, "[DEBUG] Show debug values");
}

init
{
    var scn = new SignatureScanner(game, game.MainModule.BaseAddress, game.MainModule.ModuleMemorySize);
    SigScanTarget.OnFoundCallback getRel = (p,s,ptr) => ptr + 4 + game.ReadValue<int>(ptr);

    var gameEngineTrg = new SigScanTarget(8, "E8 ?? ?? ?? ?? 48 39 35 ?? ?? ?? ?? 0F 85 ?? ?? ?? ?? 48 8B 0D") { OnFound = getRel };
    vars.GameEnginePtr = scn.Scan(gameEngineTrg);

    var uWorldTrg = new SigScanTarget(3, "48 8B 05 ?? ?? ?? ?? 4C 8B C3 49 8B 08") { OnFound = getRel };
    vars.UWorldPtr = scn.Scan(uWorldTrg);

    var syncLoadTrg = new SigScanTarget(5, "89 43 60 8B 05 ?? ?? ?? ??") { OnFound = getRel };
    vars.SyncLoadCounterPtr = scn.Scan(syncLoadTrg);

    var fNamePoolTrg = new SigScanTarget(10, "40 38 3D ?? ?? ?? ?? 48 8D 15") { OnFound = getRel };
    var fNamePool = scn.Scan(fNamePoolTrg);

    vars.FNameToString = (Func<ulong, string>)(fName =>
    {
        var number   = (fName & 0xFFFFFFFF00000000) >> 0x20;
        var chunkIdx = (fName & 0x00000000FFFF0000) >> 0x10;
        var nameIdx  = (fName & 0x000000000000FFFF) >> 0x00;
        var chunk = game.ReadPointer(fNamePool + 0x10 + (int)chunkIdx * 0x8);
        var nameEntry = chunk + (int)nameIdx * 0x2;
        var length = game.ReadValue<short>(nameEntry) >> 6;
        var name = game.ReadString(nameEntry + 0x2, length);
        return number == 0 ? name : name + "_" + number;
    });

    vars.Log("GameEngine Ptr: 0x"+vars.GameEnginePtr.ToString("X"));
    vars.Log("uWorld Ptr: 0x"+vars.UWorldPtr.ToString("X"));
    vars.Log("FNamePool Ptr: 0x"+fNamePool.ToString("X"));

    current.worldName = old.worldName = "None";
}

update
{
    IntPtr uWorld = game.ReadValue<IntPtr>((IntPtr)vars.UWorldPtr);
    var worldFName = game.ReadValue<ulong>(uWorld + 0x18);
    var worldName = vars.FNameToString(worldFName);
    current.worldName = (worldName == "None") ? old.worldName : worldName;

    // GameEngine.GameInstance.SaveGameManager
    // var saveGamePtr = new DeepPointer(vars.GameEnginePtr, 0x1178, 0x2D8).Deref<IntPtr>(game);
    // vars.Loading = game.ReadValue<bool>(saveGamePtr + 0x924);

    var syncLoadCount = game.ReadValue<int>((IntPtr)vars.SyncLoadCounterPtr);
    current.loading = syncLoadCount != 0;

    // GameEngine.GameInstance.LocalPlayers[0].PlayerController.PlayerCharacter
    var playerCharacterPtr = new DeepPointer(vars.GameEnginePtr, 0x1178, 0x38, 0x0, 0x30, 0x378).Deref<IntPtr>(game);
    var playerMovementPtr = game.ReadValue<IntPtr>((IntPtr)(playerCharacterPtr + 0x3C0));

    var xVel = game.ReadValue<double>((IntPtr)(playerMovementPtr + 0x130));
    var yVel = game.ReadValue<double>((IntPtr)(playerMovementPtr + 0x138));
    var hVel = Math.Sqrt((xVel * xVel) + (yVel * yVel)) / 100;


    if(settings["speedometer"])
    vars.SetTextComponent("Speed", hVel.ToString("0.00") + " m/s");

    if(settings["debugText"])
    {
        vars.SetTextComponent("Time", System.DateTime.Now.ToString());
        vars.SetTextComponent("WorldName", current.worldName);
        vars.SetTextComponent("syncLoadCount", syncLoadCount.ToString());
        vars.SetTextComponent("Loading", current.loading.ToString());
    }

    if(current.worldName != old.worldName)
    {
        vars.Log(old.worldName+" => "+current.worldName);
    }
}

start
{
    // [The Outer Worlds 2 ASL] CharacterCreation_Lite => 0501_PS_Intro_P
    return (current.worldName == "0501_PS_Intro_P" && old.worldName == "CharacterCreation_Lite");
}

reset
{
    // [The Outer Worlds 2 ASL] ConversationalMainMenu => CharacterCreation_Lite
    return (current.worldName == "CharacterCreation_Lite" && old.worldName == "ConversationalMainMenu");
}

onStart
{
    timer.IsGameTimePaused = true;
}

isLoading
{
    return current.loading;
}