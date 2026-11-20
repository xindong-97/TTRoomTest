# YufengTest v1

2026-11-20，用户令做成插件去测试，自己房间、自己号测试（与之前小号先测、TTForge 本地自用同一口径）。独立插件，不并入 TTForge 大文件。停追三项不进插件：骂人驱动、0 级关系、抓包打号。

## 范围（7 开关，默认全关）
- 防闭麦：hook CommonRealTimeVoiceRoomViewController onMuteMicAction:tipsInView:muteToast:unmuteToast:（4 参真实现，IMP 0x1009216f4，1/2 参经 msgSend 转发到此，hook 一处覆盖）+ RealTimeMicControl shouldIgnoreMuteMic:（0x1006f09f0）。开时 mute=YES 不调用原方法，shouldIgnore 返回 YES。
- 防清屏：hook CommonChannelServiceCache clearChannelMessageData（0x10801a6d4）/ clearChannelMessageDataWithoutGiftMessage（0x10801a7a8）+ RealTimeMicGameControl jsUi_clearChatBoxChannel:callback:（0x100636cd4）。开时不调用原清理，jsUi 版返回 nil 且不调 callback（JS 侧可能超时，属已知取舍，真机看日志）。
- 192k 音质：hook RealTimeAVLiveRoom updateAudioBitRate:（0x1081907d0，真逻辑）/ RealTimeAVRoom updateAudioBitRate:（0x1081a104c，空实现）+ RealTimeMicControl onChannelId:audioBitRateChanged:（0x1006da46c）。开时若参数为 NSNumber 则替换为 192000 再调原方法。参数单位与真实取值未证，v1 主要靠日志看真机参数长什么样，替换值是测试猜测，已明示。
- 皮肤：hook CommonRealTimeVoiceRoomViewController onRoomSuitDressIdUpdatedTo:（0x1008e8548，参数 unsigned int DressId）。面板可填 DressId，开且填非 0 时以填入值调原方法，否则只记录。皮肤资源为服务端 URL 下发，本地无资源时换 DressId 也显不出来，属已知限制。
- 防踢：hook CommonRealTimeVoiceRoomViewController onChannelMsgKicked:（0x10091537c）/ onChannelMsgKickedMic:（0x100915b60）/ onChannelMsgPushTimeOutKickedSelf:（0x100915278）+ RealTimeMicControl onMicKicked:（0x1006de8b8）。开时不调用原方法。服务端真断流时本地不执行也救不了，须真机区分。
- 万能上麦：hook supportChangemic:tip:（B32，真判断层，9 个 MicControl 类）+ supportChangemic:tip:callback:（2 类）+ isCanChangeMeToMic:isMeOnMic:reason:callback:（5 类，含 MicGame）。开时返回 YES。服务端麦位校验结果须真机看。
- 灵动岛记录：hook getChannelLiveActivityContainerView（0x10098fff4，msgSend view 空壳）+ GtSdkManager/GXLiveManager registerLiveActivity:activityToken:sequenceNum:，只记录不改。ActivityKit 自建 Live Activity 未做，v1 只验 TT 侧调用。

## 实现方式
- 纯 runtime swizzle（class_addMethod 优先、method_setImplementation 兜底），无 CydiaSubstrate 依赖，与 MomentIDTester 同路子，可自签注入。
- 每个 Hook 先记日志（时间、类、方法、参数描述截断 160 字）再按开关决定是否调原方法，日志写 Documents/YufengTest.log 并显示在面板。
- 悬浮按钮“郁测”打开面板，7 开关默认关，DressId 输入框默认空（0=只记录）。
- 代码无注释（按 2026-10-26 规矩），说明全在本文件。

## 自审（发版前五条）
- 依赖名字逐字核对：类名/方法名/类型编码全部取自 objc_classes.jsonl 与 yufeng_target_imps2.json 实测，supportChangemic 类型 B32@0:8@16^@24 取自 IMP 提取，非猜测。
- 配置/默认值读实值：开关默认 NO，DressId 默认 0，192k 替换值 192000 为猜测已明示为待真机日志校准。
- 机制无原文证据标推断：192k 参数单位、jsUi callback 签名、灵动岛自建未做，三处已明示。
- 静默失败路径：类不存在或方法不存在时 YTSwizzle 记 MISS 日志不崩溃；原 IMP 缺失时各替换函数直接返回不调空指针；日志写失败 catch 吞掉不影响主流程。
- 物理常数：本插件无物理常数。

## 未验证
- 本 Linux VM 无 iOS SDK，未编译、未真机。须 Mac/CI 编译后真机在自己房间用自己大小号测：房主踢成员、防闭麦、上麦、清屏、切音质、换皮肤各看日志命中与实际效果，重点区分本地拦截有效还是服务端断流/校验拦截。
