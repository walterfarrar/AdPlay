package com.adplay.app.data

import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.functions.FirebaseFunctions
import com.google.firebase.functions.ktx.functions
import com.google.firebase.ktx.Firebase
import com.google.gson.Gson
import kotlinx.coroutines.tasks.await

class ApiClient {
    private val auth = FirebaseAuth.getInstance()
    private val functions: FirebaseFunctions = Firebase.functions("us-central1")
    private val gson = Gson()

    suspend fun ensureSignedIn() {
        if (auth.currentUser == null) {
            auth.signInAnonymously().await()
        }
    }

    suspend fun fetchState(): Pair<GameState, Tunables?> {
        ensureSignedIn()
        val result = functions.getHttpsCallable("getState").call().await()
        @Suppress("UNCHECKED_CAST")
        val data = result.getData() as Map<String, Any?>
        val state = gson.fromJson(gson.toJson(data["state"]), GameState::class.java)
        val tunables = data["tunables"]?.let {
            gson.fromJson(gson.toJson(it), Tunables::class.java)
        }
        return state to tunables
    }

    suspend fun tap(): GameState {
        ensureSignedIn()
        val result = functions.getHttpsCallable("gameTap").call().await()
        @Suppress("UNCHECKED_CAST")
        val data = result.getData() as Map<String, Any?>
        return gson.fromJson(gson.toJson(data["state"]), GameState::class.java)
    }

    suspend fun mockComplete(boost: BoostType): GameState {
        ensureSignedIn()
        val result = functions
            .getHttpsCallable("mockCompleteBoost")
            .call(hashMapOf("boostType" to boost.apiValue))
            .await()
        @Suppress("UNCHECKED_CAST")
        val data = result.getData() as Map<String, Any?>
        return gson.fromJson(gson.toJson(data["state"]), GameState::class.java)
    }

    suspend fun debugReset(): GameState {
        ensureSignedIn()
        val result = functions.getHttpsCallable("debugReset").call().await()
        @Suppress("UNCHECKED_CAST")
        val data = result.getData() as Map<String, Any?>
        return gson.fromJson(gson.toJson(data["state"]), GameState::class.java)
    }

    suspend fun requestWithdrawal(amountSats: Int, bolt11: String): GameState {
        ensureSignedIn()
        val result = functions
            .getHttpsCallable("requestWithdrawal")
            .call(hashMapOf("amountSats" to amountSats, "bolt11" to bolt11))
            .await()
        @Suppress("UNCHECKED_CAST")
        val data = result.getData() as Map<String, Any?>
        return gson.fromJson(gson.toJson(data["state"]), GameState::class.java)
    }

    suspend fun myWithdrawals(): List<Withdrawal> {
        ensureSignedIn()
        val result = functions.getHttpsCallable("myWithdrawals").call().await()
        @Suppress("UNCHECKED_CAST")
        val data = result.getData() as Map<String, Any?>
        val list = data["withdrawals"] as? List<*> ?: emptyList<Any>()
        return list.map { gson.fromJson(gson.toJson(it), Withdrawal::class.java) }
    }
}

class ApiException(val code: Int, message: String) : Exception(message)
