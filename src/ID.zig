const AK = @import("wwise-zig");

// TODO: Convert this using a build step and auto-create an importable module
pub const EVENTS = struct {
    pub const DISABLE_MICROPHONE_DELAY: AK.AkUniqueID = 6251382;
    pub const ENABLE_MICROPHONE_DELAY: AK.AkUniqueID = 3533161767;
    pub const ENTER_AREA_1: AK.AkUniqueID = 2507024135;
    pub const ENTER_AREA_2: AK.AkUniqueID = 2507024132;
    pub const IM_1_ONE_ENEMY_WANTS_TO_FIGHT: AK.AkUniqueID = 2221704914;
    pub const IM_2_TWO_ENEMIES_WANT_TO_FIGHT: AK.AkUniqueID = 3753105098;
    pub const IM_3_SURRONDED_BY_ENEMIES: AK.AkUniqueID = 1350929071;
    pub const IM_4_DEATH_IS_COMING: AK.AkUniqueID = 3175089270;
    pub const IM_COMMUNICATION_BEGIN: AK.AkUniqueID = 2160840676;
    pub const IM_EXPLORE: AK.AkUniqueID = 3280047539;
    pub const IM_GAMEOVER: AK.AkUniqueID = 3455955770;
    pub const IM_START: AK.AkUniqueID = 3952084898;
    pub const IM_THEYAREHOSTILE: AK.AkUniqueID = 2841817544;
    pub const IM_WINTHEFIGHT: AK.AkUniqueID = 1133905385;
    pub const METRONOME_POSTMIDI: AK.AkUniqueID = 2710399919;
    pub const PAUSE_ALL: AK.AkUniqueID = 3864097025;
    pub const PAUSE_ALL_GLOBAL: AK.AkUniqueID = 3493516265;
    pub const PLAY_3D_AUDIO_DEMO: AK.AkUniqueID = 4057320454;
    pub const PLAY_3DBUS_DEMO: AK.AkUniqueID = 834165051;
    pub const PLAY_AMBIENCE_QUAD: AK.AkUniqueID = 146788224;
    pub const PLAY_CHIRP: AK.AkUniqueID = 3187155090;
    pub const PLAY_CLUSTER: AK.AkUniqueID = 2148126352;
    pub const PLAY_ENGINE: AK.AkUniqueID = 639345804;
    pub const PLAY_FOOTSTEP: AK.AkUniqueID = 1602358412;
    pub const PLAY_FOOTSTEPS: AK.AkUniqueID = 3854155799;
    pub const PLAY_HELLO: AK.AkUniqueID = 2952797154;
    pub const PLAY_HELLO_REVERB: AK.AkUniqueID = 3795249249;
    pub const PLAY_MARKERS_TEST: AK.AkUniqueID = 3368417626;
    pub const PLAY_MICROPHONE: AK.AkUniqueID = 1324678662;
    pub const PLAY_NONRECORDABLEMUSIC: AK.AkUniqueID = 3873244457;
    pub const PLAY_POSITIONING_DEMO: AK.AkUniqueID = 1237313597;
    pub const PLAY_RECORDABLEMUSIC: AK.AkUniqueID = 2567011622;
    pub const PLAY_ROOM_EMITTER: AK.AkUniqueID = 2172342284;
    pub const PLAY_SANDSTEP: AK.AkUniqueID = 2266299534;
    pub const PLAY_THREE_NUMBERS_IN_A_ROW: AK.AkUniqueID = 4142087708;
    pub const PLAYMUSICDEMO1: AK.AkUniqueID = 519773714;
    pub const PLAYMUSICDEMO2: AK.AkUniqueID = 519773713;
    pub const PLAYMUSICDEMO3: AK.AkUniqueID = 519773712;
    pub const RESUME_ALL: AK.AkUniqueID = 3679762312;
    pub const RESUME_ALL_GLOBAL: AK.AkUniqueID = 1327221850;
    pub const STOP_3DBUS_DEMO: AK.AkUniqueID = 246841725;
    pub const STOP_ALL: AK.AkUniqueID = 452547817;
    pub const STOP_CLUSTER: AK.AkUniqueID = 2775363470;
    pub const STOP_ENGINE: AK.AkUniqueID = 37214798;
    pub const STOP_MICROPHONE: AK.AkUniqueID = 3629954576;
};

pub const DIALOGUE_EVENTS = struct {
    pub const OBJECTIVE_STATUS: AK.AkUniqueID = 3970659059;
    pub const UNIT_UNDER_ATTACK: AK.AkUniqueID = 3585983975;
    pub const WALKIETALKIE: AK.AkUniqueID = 4110439188;
};

pub const STATES = struct {
    pub const HOSTILE = struct {
        pub const GROUP: AK.AkUniqueID = 3712907969;

        pub const STATE = struct {
            pub const BUM: AK.AkUniqueID = 714721627;
            pub const GANG: AK.AkUniqueID = 685704824;
            pub const NONE: AK.AkUniqueID = 748895195;
        };
    };

    pub const LOCATION = struct {
        pub const GROUP: AK.AkUniqueID = 1176052424;

        pub const STATE = struct {
            pub const ALLEY: AK.AkUniqueID = 672587556;
            pub const HANGAR: AK.AkUniqueID = 2192450996;
            pub const NONE: AK.AkUniqueID = 748895195;
            pub const STREET: AK.AkUniqueID = 4142189312;
        };
    };

    pub const MUSIC = struct {
        pub const GROUP: AK.AkUniqueID = 3991942870;

        pub const STATE = struct {
            pub const EXPLORING: AK.AkUniqueID = 1823678183;
            pub const FIGHT: AK.AkUniqueID = 514064485;
            pub const FIGHT_DAMAGED: AK.AkUniqueID = 886139701;
            pub const FIGHT_DYING: AK.AkUniqueID = 4222988787;
            pub const FIGHT_LOWHEALTH: AK.AkUniqueID = 1420167880;
            pub const GAMEOVER: AK.AkUniqueID = 4158285989;
            pub const NONE: AK.AkUniqueID = 748895195;
            pub const PLAYING: AK.AkUniqueID = 1852808225;
            pub const WINNING_THEFIGHT: AK.AkUniqueID = 1323211483;
        };
    };

    pub const OBJECTIVE = struct {
        pub const GROUP: AK.AkUniqueID = 6899006;

        pub const STATE = struct {
            pub const DEFUSEBOMB: AK.AkUniqueID = 3261872615;
            pub const NEUTRALIZEHOSTILE: AK.AkUniqueID = 141419130;
            pub const NONE: AK.AkUniqueID = 748895195;
            pub const RESCUEHOSTAGE: AK.AkUniqueID = 3841112373;
        };
    };

    pub const OBJECTIVESTATUS = struct {
        pub const GROUP: AK.AkUniqueID = 3299963692;

        pub const STATE = struct {
            pub const COMPLETED: AK.AkUniqueID = 94054856;
            pub const FAILED: AK.AkUniqueID = 1655200910;
            pub const NONE: AK.AkUniqueID = 748895195;
        };
    };

    pub const PLAYERHEALTH = struct {
        pub const GROUP: AK.AkUniqueID = 151362964;

        pub const STATE = struct {
            pub const BLASTED: AK.AkUniqueID = 868398962;
            pub const NONE: AK.AkUniqueID = 748895195;
            pub const NORMAL: AK.AkUniqueID = 1160234136;
        };
    };

    pub const UNIT = struct {
        pub const GROUP: AK.AkUniqueID = 1304109583;

        pub const STATE = struct {
            pub const NONE: AK.AkUniqueID = 748895195;
            pub const UNIT_A: AK.AkUniqueID = 3004848135;
            pub const UNIT_B: AK.AkUniqueID = 3004848132;
        };
    };

    pub const WALKIETALKIE = struct {
        pub const GROUP: AK.AkUniqueID = 4110439188;

        pub const STATE = struct {
            pub const COMM_IN: AK.AkUniqueID = 1856010785;
            pub const COMM_OUT: AK.AkUniqueID = 1553720736;
            pub const NONE: AK.AkUniqueID = 748895195;
        };
    };
};

pub const SWITCHES = struct {
    pub const FOOTSTEP_GAIT = struct {
        pub const GROUP: AK.AkUniqueID = 4202554577;

        pub const SWITCH = struct {
            pub const RUN: AK.AkUniqueID = 712161704;
            pub const WALK: AK.AkUniqueID = 2108779966;
        };
    };

    pub const FOOTSTEP_WEIGHT = struct {
        pub const GROUP: AK.AkUniqueID = 246300162;

        pub const SWITCH = struct {
            pub const HEAVY: AK.AkUniqueID = 2732489590;
            pub const LIGHT: AK.AkUniqueID = 1935470627;
        };
    };

    pub const SURFACE = struct {
        pub const GROUP: AK.AkUniqueID = 1834394558;

        pub const SWITCH = struct {
            pub const DIRT: AK.AkUniqueID = 2195636714;
            pub const GRAVEL: AK.AkUniqueID = 2185786256;
            pub const METAL: AK.AkUniqueID = 2473969246;
            pub const WOOD: AK.AkUniqueID = 2058049674;
        };
    };
};

pub const GAME_PARAMETERS = struct {
    pub const ENABLE_EFFECT: AK.AkUniqueID = 2451442924;
    pub const FOOTSTEP_SPEED: AK.AkUniqueID = 3182548923;
    pub const FOOTSTEP_WEIGHT: AK.AkUniqueID = 246300162;
    pub const RPM: AK.AkUniqueID = 796049864;
};

pub const BANKS = struct {
    pub const INIT: AK.AkUniqueID = 1355168291;
    pub const BGM: AK.AkUniqueID = 412724365;
    pub const BUS3D_DEMO: AK.AkUniqueID = 3682547786;
    pub const CAR: AK.AkUniqueID = 983016381;
    pub const DIRT: AK.AkUniqueID = 2195636714;
    pub const DLLDEMO: AK.AkUniqueID = 2517646102;
    pub const DYNAMICDIALOGUE: AK.AkUniqueID = 1028808198;
    pub const EXTERNALSOURCES: AK.AkUniqueID = 480966290;
    pub const GRAVEL: AK.AkUniqueID = 2185786256;
    pub const HUMAN: AK.AkUniqueID = 3887404748;
    pub const INTERACTIVEMUSIC: AK.AkUniqueID = 2279279248;
    pub const MARKERTEST: AK.AkUniqueID = 2309453583;
    pub const METAL: AK.AkUniqueID = 2473969246;
    pub const METRONOME: AK.AkUniqueID = 3537469747;
    pub const MICROPHONE: AK.AkUniqueID = 2872041301;
    pub const MUSICCALLBACKS: AK.AkUniqueID = 4146461094;
    pub const PAUSERESUME: AK.AkUniqueID = 3699003020;
    pub const POSITIONING_DEMO: AK.AkUniqueID = 418215934;
    pub const PREPAREDEMO: AK.AkUniqueID = 3353080015;
    pub const THREED_AUDIO_DEMO: AK.AkUniqueID = 1265494800;
    pub const WOOD: AK.AkUniqueID = 2058049674;
};

pub const BUSSES = struct {
    pub const _3D_SUBMIX_BUS: AK.AkUniqueID = 1101487118;
    pub const _3D_AUDIO_DEMO: AK.AkUniqueID = 3742896575;
    pub const _3D_BUS_DEMO: AK.AkUniqueID = 4083517055;
    pub const BGM: AK.AkUniqueID = 412724365;
    pub const DRY_PATH: AK.AkUniqueID = 1673180298;
    pub const ENVIRONMENTAL_BUS: AK.AkUniqueID = 3600197733;
    pub const ENVIRONMENTS: AK.AkUniqueID = 3761286811;
    pub const GAME_PAD_BUS: AK.AkUniqueID = 3596053402;
    pub const MASTER_AUDIO_BUS: AK.AkUniqueID = 3803692087;
    pub const MUSIC: AK.AkUniqueID = 3991942870;
    pub const MUTED_FOR_USER_MUSIC: AK.AkUniqueID = 1949198961;
    pub const NON_RECORDABLE_BUS: AK.AkUniqueID = 461496087;
    pub const NON_WORLD: AK.AkUniqueID = 838047381;
    pub const PORTALS: AK.AkUniqueID = 2017263062;
    pub const SOUNDS: AK.AkUniqueID = 1492361653;
    pub const VOICES: AK.AkUniqueID = 3313685232;
    pub const VOICES_RADIO: AK.AkUniqueID = 197057172;
    pub const WET_PATH_3D: AK.AkUniqueID = 2281484271;
    pub const WET_PATH_OMNI: AK.AkUniqueID = 1410202225;
    pub const WORLD: AK.AkUniqueID = 2609808943;
};

pub const AUX_BUSSES = struct {
    pub const HANGAR_ENV: AK.AkUniqueID = 2112490296;
    pub const LISTENERENV: AK.AkUniqueID = 924456902;
    pub const OUTSIDE: AK.AkUniqueID = 438105790;
    pub const ROOM: AK.AkUniqueID = 2077253480;
    pub const ROOM1: AK.AkUniqueID = 1359360137;
    pub const ROOM2: AK.AkUniqueID = 1359360138;
};
pub const AUDIO_DEVICES = struct {
    pub const COMMUNICATION_OUTPUT: AK.AkUniqueID = 3884583641;
    pub const CONTROLLER_HEADPHONES: AK.AkUniqueID = 2868300805;
    pub const DVR_BYPASS: AK.AkUniqueID = 1535232814;
    pub const NO_OUTPUT: AK.AkUniqueID = 2317455096;
    pub const PAD_OUTPUT: AK.AkUniqueID = 666305828;
    pub const SYSTEM: AK.AkUniqueID = 3859886410;
};

pub const EXTERNAL_SOURCES = struct {
    pub const EXTERN_2ND_NUMBER: AK.AkUniqueID = 293435250;
    pub const EXTERN_3RD_NUMBER: AK.AkUniqueID = 978954801;
    pub const EXTERN_1ST_NUMBER: AK.AkUniqueID = 4004957102;
};
