package com.adplay.app.ads

enum class AdFillResult {
    /** User watched and earned the reward. */
    EARNED,

    /** No inventory / load or present failed — try the next network. */
    UNAVAILABLE,

    /** Ad was shown; user closed without earning — do not fall through. */
    DECLINED,
}
