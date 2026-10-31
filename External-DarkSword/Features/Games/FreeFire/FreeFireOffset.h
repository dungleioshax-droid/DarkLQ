//
//  FreeFireOffset.h
//  External-DarkSword
//
//  Offset updated from /home/dungle/FFDUMP (Free Fire TH 1.132.1)
//

#ifndef FreeFireOffset_h
#define FreeFireOffset_h

#pragma once
#include <stdint.h>

// Function RVAs
inline constexpr uint64_t kGameFacade_CurrentLocalPlayer = 0x591BD2C;
inline constexpr uint64_t kGameFacade_GetLocalPlayerOrObServer = 0x5919628;
inline constexpr uint64_t kGameFacade_IsLocalTeammate = 0x591C5B4;
inline constexpr uint64_t kGameFacade_CCtor = 0x5944B44;
inline constexpr uint64_t kGameFacade_SetCurrentGame = 0x5918864;
inline constexpr uint64_t kGameFacade_GetGameServerPort = 0x5913128;
inline constexpr uint64_t kGameFacade_GetGameServerAddr = 0x5912F20;
inline constexpr uint64_t kGameFacade_GetIsCameraMode = 0x5913788;
inline constexpr uint64_t kGameFacade_CurrentLocalPlayerID = 0x591D5EC;

// MethodInfo RVAs (from ScriptMetadataMethod in FFDUMP)
inline constexpr uint64_t kMethodInfo_GameFacade_CCtor = 0xFCA16C68;
inline constexpr uint64_t kMethodInfo_GameFacade_CurrentLocalPlayer = 0xFCA0C298;
inline constexpr uint64_t kMethodInfo_GameFacade_SetCurrentGame = 0xFCA0AEA8;

inline constexpr uint64_t kMatchGame_GetCameraControllerManager = 0x5A9CFC4;
inline constexpr uint64_t kMatchGame_GetRepEntity = 0x5A9D2C8;

inline constexpr uint64_t kCamera_GetMain = 0x8CFF0B4;
inline constexpr uint64_t kCamera_WorldToCameraMatrixInjected = 0x8CFE29C;
inline constexpr uint64_t kCamera_ProjectionMatrixInjected = 0x8CFE444;
inline constexpr uint64_t kCamera_WorldToScreenPoint = 0x8CFE9C0;

inline constexpr uint64_t kTransform_GetPositionInjected = 0x8D6C250;
inline constexpr uint64_t kEntity_GetPosition = 0x6B49D04;
inline constexpr uint64_t kEntity_GetCachedTransform = 0x6B49C14;

inline constexpr uint64_t kPlayer_GetCurHP = 0x56AA7C8;
inline constexpr uint64_t kPlayer_GetMaxHP = 0x5613110;
inline constexpr uint64_t kAttackableEntity_GetIsDead = 0x58C44AC;
inline constexpr uint64_t kPlayer_GetCameraTrackableEntityPosition = 0x56E4CD0;
inline constexpr uint64_t kPlayer_GetCameraTrackableEntityTopPosition = 0x56E4FD8;
inline constexpr uint64_t kAttackableEntity_GetAttackableCenterWS = 0x58C458C;

// GameFacade Static Fields
inline constexpr uint64_t kGameFacadeStatic_CurrentGame = 0x00;
inline constexpr uint64_t kGameFacadeStatic_CurrentMatchGame = 0x08;
inline constexpr uint64_t kGameFacadeStatic_LocalPlayerUserID = 0x58;

// BaseGame & UIFrontEndScene Fields (Training Ground / Social Area)
inline constexpr uint64_t kMethodInfo_BaseGame_CCtor = 0x1FB5CD28;
inline constexpr uint64_t kBaseGame_UIScene = 0x10;
inline constexpr uint64_t kBaseGameStatic_sTickedEntities = 0x00;
inline constexpr uint64_t kBaseGameStatic_sAllEntities = 0x08;
inline constexpr uint64_t kBaseGameStatic_sAllLEntities = 0x10;
inline constexpr uint64_t kUIFrontEndScene_UI3DCamera = 0x170;
inline constexpr uint64_t kUIFrontEndScene_BgCamera = 0x178;
inline constexpr uint64_t kUIFrontEndScene_LobbyCamGyro = 0x190;
inline constexpr uint64_t kGyroCameraController_Cam1 = 0x20;

// FrontEndGame & PostEffectManager (Training Ground / Social Area)
inline constexpr uint64_t kFrontEndGame_PostEffect = 0x90;
inline constexpr uint64_t kPostEffectManager_ExtraCameras = 0x20;
inline constexpr uint64_t kPostEffectManager_OwnerCamera = 0x38;

// UICamera
inline constexpr uint64_t kMethodInfo_UICamera_CCtor = 0x19665B30;
inline constexpr uint64_t kUICameraStatic_Current = 0xB0;
inline constexpr uint64_t kUICameraStatic_CurrentCamera = 0xB8;
inline constexpr uint64_t kUICamera_mCam = 0x98;

// MatchGame Fields
inline constexpr uint64_t kMatchGame_ReplicationEntities = 0xC0;
inline constexpr uint64_t kMatchGame_CameraControllerManager = 0xD8;

// CameraControllerManager Fields
inline constexpr uint64_t kCameraControllerManager_MainCamera = 0x20;
inline constexpr uint64_t kCameraControllerManager_SubCamera = 0x28;

// Unity Object & Native Camera
inline constexpr uint64_t kUnityObject_CachedPtr = 0x10;
inline constexpr uint64_t kNativeCamera_WorldToCamera = 0x80;
inline constexpr uint64_t kNativeCamera_Projection = 0xC0;
inline constexpr uint64_t kNativeCamera_WorldToClip = 0x100;

// Entity & Player Fields
inline constexpr uint64_t kEntity_CachedTransform = 0x58;
inline constexpr uint64_t kPlayer_OriginalNickName = 0x498;
inline constexpr uint64_t kPlayer_TeamModeID = 0x434;
inline constexpr uint64_t kPlayer_UserID = 0x4A8;
inline constexpr uint64_t kPlayer_IsClientBot = 0x4A0;
inline constexpr uint64_t kPlayer_GetInVehicle = 0x4F8;
inline constexpr uint64_t kAttackableEntity_IsDeadFlag = 0x7C;
inline constexpr uint64_t kPlayer_Position1 = 0xD0;
inline constexpr uint64_t kPlayer_Position2 = 0x10C;
inline constexpr uint64_t kPlayer_Position3 = 0x270;

// System.Collections.Generic.Dictionary Layout
inline constexpr uint64_t kDictionary_Buckets = 0x10;
inline constexpr uint64_t kDictionary_Entries = 0x18;
inline constexpr uint64_t kDictionary_Count = 0x20;

// Il2Cpp Array Layout
inline constexpr uint64_t kArray_Length = 0x18;
inline constexpr uint64_t kArray_Vector = 0x20;

// Dictionary Entry
inline constexpr uint64_t kEntry_Size = 0x18;
inline constexpr uint64_t kEntry_HashCode = 0x00;
inline constexpr uint64_t kEntry_Key = 0x08;
inline constexpr uint64_t kEntry_Value = 0x10;

// System.String Layout
inline constexpr uint64_t kSystemString_Length = 0x10;
inline constexpr uint64_t kSystemString_Chars = 0x14;

// Il2CppClass & MethodInfo Layout
inline constexpr uint64_t kMethodInfo_Klass = 0x18;
inline constexpr uint64_t kIl2CppClass_StaticFields = 0xB8;
inline constexpr uint64_t kIl2CppClass_Parent = 0x58;
inline constexpr uint64_t kIl2CppClass_Name = 0x10;

#endif /* FreeFireOffset_h */
