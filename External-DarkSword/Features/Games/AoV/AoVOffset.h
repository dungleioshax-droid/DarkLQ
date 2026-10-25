//
//  AoVOffset.h
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/6/26.
//

#ifndef AoVOffset_h
#define AoVOffset_h

#pragma once
#include <stdint.h>

/*
Offset updated from /home/dungle/LienQuanDUMP
*/

// Function RVAs
inline constexpr uint64_t kOnCameraHeightChanged = 0x540F2C8;

// MethodInfo RVAs => Read singleton
inline constexpr uint64_t kCBattleSystem = 0xD10D510;
inline constexpr uint64_t kBattleLogic = 0xD10D308;
inline constexpr uint64_t kCHeroSelectNormalSystem = 0xD10D928;
inline constexpr uint64_t kCHeroSelectBaseSystem = 0xD10D8B0;
inline constexpr uint64_t kCRoleInfoManager = 0xD10DF40;
inline constexpr uint64_t kCLadderSystem = 0xD10DA28;
inline constexpr uint64_t kCameraSystem = 0xD108150;  // MonoSingleton
inline constexpr uint64_t kGameFramework = 0xD108200; // MonoSingleton
inline constexpr uint64_t kLLogicCore = 0xD10E9C0;
inline constexpr uint64_t kAdrKyriosFramework = 0xD1082A0;

// Il2Cpp layout
inline constexpr uint64_t kMethodInfo_Klass = 0x20;
inline constexpr uint64_t kIl2CppClass_StaticFields = 0xB8;
inline constexpr uint64_t kIl2CppClass_RgctxData = 0xC0;
inline constexpr uint64_t kRgctx_ClosedClass = 0x10; // rgctx[2]

// Field offset
/// class CBattleSystem | public bool m_isInBattle; // 0x8
inline constexpr uint64_t kCBattleSystem_IsInBattle = 0x08;

/// class CameraSystem | private float zoomRateFromAge; // 0x3C
inline constexpr uint64_t kCameraSystem_ZoomRateFromAge = 0x3C;

/// class CameraSystem | public Moba_Camera MobaCamera; // 0x18
inline constexpr uint64_t kCameraSystem_MobaCamera = 0x18;

/// class CameraSystem | private Camera m_mainCamera; // 0x108
inline constexpr uint64_t kCameraSystem_MainCamera = 0x108;

/// class Moba_Camera | public Moba_Camera_Requirements requirements; // 0x68
inline constexpr uint64_t kMobaCamera_Requirements = 0x68;

/// class Moba_Camera_Requirements | public Camera camera; // 0x18
inline constexpr uint64_t kMobaRequirement_Camera = 0x18;

/// class Object | private IntPtr m_CachedPtr; // 0x8
inline constexpr uint64_t kUnityObject_CachedPtr = 0x08;

inline constexpr uint64_t kNativeCamera_WorldToCamera = 0x80;
inline constexpr uint64_t kNativeCamera_Projection = 0xC0;
inline constexpr uint64_t kNativeCamera_WorldToClip = 0x100;

/// class KyriosFramework | private ActorManager _actorManager; // 0x28
inline constexpr uint64_t kKyriosFramework_ActorManager = 0x28;

/// class KyriosFramework | private VHostLogic _hostLogic; // 0x50
inline constexpr uint64_t kKyriosFramework_HostLogic = 0x50;

/// class VHostLogic | private Player <hostPlayer>k__BackingField; // 0x8
inline constexpr uint64_t kVHostLogic_HostPlayer = 0x08;

/// class Player: PlayerBase | public COM_PLAYERCAMP PlayerCamp; // 0x30
inline constexpr uint64_t kPlayer_PlayerCamp = 0x30;

/// class Player | public PoolObjHandle<ActorLinker> CaptainLinker; // 0x198
inline constexpr uint64_t kPlayer_CaptainLinker = 0x198;

/// class ActorManager | public List<PoolObjHandle<ActorLinker>> HeroActors; //
/// 0x20
inline constexpr uint64_t kActorManager_HeroActors = 0x20;

/// class ActorLinker | public ValueLinkerComponent ValueComponent; // 0x28
inline constexpr uint64_t kActorLinker_ValueComponent = 0x28;

/// class ActorLinker | public ObjLinkerWrapper ActorControl; // 0x30
inline constexpr uint64_t kActorLinker_ActorControl = 0x30;

/// class ActorLinker | public ActorConfig ObjLinker; // 0x128
inline constexpr uint64_t kActorLinker_ObjLinker = 0x128;

/// class ActorLinker | private VInt3 _forward; // 0x180
inline constexpr uint64_t kActorLinker_Forward = 0x180;

/// class ActorLinker | public VInt3 _location; // 0x18C
inline constexpr uint64_t kActorLinker_Location = 0x18C;

/// class ActorLinker | private bool mIsHostCtrlActor; // 0x1B0
inline constexpr uint64_t kActorLinker_IsHostControlled = 0x1B0;

/// class ActorLinker | private bool <bVisible>k__BackingField; // 0x1DD
inline constexpr uint64_t kActorLinker_Visible = 0x1DD;

/// public struct ActorMeta // TypeDefIndex: 9790
/// {
///    // Fields
///    public int ConfigId; // 0x0
///    public uint PlayerId; // 0x4
///    public uint HostObjId; // 0x8
///    public int HostConfigId; // 0xC
///    public ActorTypeDef ActorType; // 0x10
///    public COM_PLAYERCAMP ActorCamp; // 0x14
///    ...
/// }
///
/// public class ActorLinker
/// {
///     ...
///     public ActorMeta TheActorMeta; // 0x218
///     public ActorStaticData TheStaticData; // 0x2A0
///     ...
/// }
///
/// => kActorLinker_Camp = 0x218 + 0x14 = 0x22C
inline constexpr uint64_t kActorLinker_Camp = 0x22C;

/// class LActorRoot | public ActorMeta TheActorMeta; // 0x58
/// 0x58 + 0x14 ( ActorCamp) = 0x6C
inline constexpr uint64_t kLActorRoot_Camp = 0x6C;

/// class ActorConfig | public int ConfigID; // 0x1C
inline constexpr uint64_t kActorConfig_ConfigID = 0x1C;

/// class ObjLinkerWrapper | public ObjBehaviMode myBehavior; // 0x30
inline constexpr uint64_t kObjLinkerWrapper_Behavior = 0x30;

/// class ValueLinkerComponent | private int <actorHp>k__BackingField; // 0x40
inline constexpr uint64_t kValueLinker_ActorHp = 0x40;

/// class ValueLinkerComponent | private int <actorHpTotal>k__BackingField; //
/// 0x44
inline constexpr uint64_t kValueLinker_ActorHpTotal = 0x44;

/// class LLogicCore | private LDeskBase <curUpdatingDesk>k__BackingField; //
/// 0x40
inline constexpr uint64_t kLLogicCore_CurUpdatingDesk = 0x40;

/// class LLogicCore | private ListView<LDeskBase> instances; // 0x48
inline constexpr uint64_t kLLogicCore_Instances = 0x48;

/// class ListView<T> : ListViewBase | protected List<object> Context; // 0x8
inline constexpr uint64_t kListView_Context = 0x08;

/// class LDeskBase | private LBattleLogic <DeskBattleLogic>k__BackingField; //
/// 0x38
inline constexpr uint64_t kLDeskBase_DeskBattleLogic = 0x38;

/// class LBattleLogic | private LGameActorMgr <gameActorMgr>k__BackingField; //
/// 0xF8
inline constexpr uint64_t kLBattleLogic_GameActorMgr = 0xF8;

/// class LGameActorMgr | public List<PoolObjHandle<LActorRoot>> HeroActors; //
/// 0x48
inline constexpr uint64_t kLGameActorMgr_HeroActors = 0x48;

/// class LGameActorMgr | public List<PoolObjHandle<LActorRoot>> MonsterActors;
/// 0x70
inline constexpr uint64_t kLGameActorMgr_MonsterActors = 0x70;

/// class LGameActorMgr | public List<PoolObjHandle<LActorRoot>> SoldierActors;
/// 0xA0
inline constexpr uint64_t kLGameActorMgr_SoldierActors = 0xA0;

/// class LActorRoot | private VInt3 _location; // 0xE0
inline constexpr uint64_t kLActorRoot_Location = 0xE0;

/// class LActorRoot | private VInt3 _forward; // 0xEC
inline constexpr uint64_t kLActorRoot_Forward = 0xEC;

/// class LActorRoot | public LObjWrapper ActorControl; // 0x308
inline constexpr uint64_t kLActorRoot_ActorControl = 0x308;

/// class LActorRoot | public ValuePropertyComponent ValueComponent; // 0x338
inline constexpr uint64_t kLActorRoot_ValueComponent = 0x338;

/// class LActorRoot | public HorizonMarker HorizonMarker; // 0x390
inline constexpr uint64_t kLActorRoot_HorizonMarker = 0x390;

/// class HorizonMarker | private HorizonMarker.CampMarker[] _campMarkers; //
/// 0x48
inline constexpr uint64_t kHorizonMarker_CampMarkers = 0x48;

/// class HorizonMarker.CampMarker | private COM_PLAYERCAMP _camp; // 0x20
inline constexpr uint64_t kHorizonCampMarker_Camp = 0x20;

/// class HorizonMarker.CampMarker | private bool _isForceShow; // 0x50
inline constexpr uint64_t kHorizonCampMarker_IsForceShow = 0x50;

/// class HorizonMarker.CampMarker | private int FadingCounter_; // 0x64
inline constexpr uint64_t kHorizonCampMarker_FadingCounter = 0x64;

/// class LObjWrapper | public ObjBehaviMode myBehavior; // 0x4C
inline constexpr uint64_t kLObjWrapper_DeadState = 0x4C;

/// class ValuePropertyComponent | private CrypticInt32 _nObjCurHp; // 0x50
inline constexpr uint64_t kValueProperty_CurrentHp = 0x50;

/// template <typename T> struct Il2CppList {
///  Il2CppClass *klass;      // 0x00
///  Il2CppArray<T> *items;   // 0x08
///  int size;                // 0x10
///  int version;             // 0x14
///  void *syncRootOrUnknown; // 0x18
/// }
inline constexpr uint64_t kList_Items = 0x08;
inline constexpr uint64_t kList_Size = 0x10;

/// template <typename T> struct Il2CppArray {
///  Il2CppClass *klass; // 0x00
///  void *bounds;       // 0x08
///  uint64_t length;    // 0x10
///  T m_Items[1];       // 0x18
/// }
inline constexpr uint64_t kArray_Length = 0x10;
inline constexpr uint64_t kArray_Items = 0x18;

/// template <typename T> struct PoolObjHandle<T> {
///  uint32_t _handleSeq;  // +0x00
///  // padding 4 byte       +0x04
///  T* _handleObj;        // +0x08
/// }; // sizeof = 0x10
inline constexpr uint64_t kPoolObjHandle_Size = 0x10;
inline constexpr uint64_t kPoolObjHandle_Object = 0x08;

#endif /* AoVOffset_h */
