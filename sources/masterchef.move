module MasterChefDeployer::MasterChef {
    use std::signer;
    use std::vector;
    use std::event;
    use std::ASCII::string;
    use std::type_info::{ Self, TypeInfo };
    use aptos_framework::timestamp;
    use aptos_framework::coin::{
        Self, Coin, MintCapability, FreezeCapability, BurnCapability
    };
    use aptos_framework::account::{ Self, SignerCapability };

    /// When already exists on account
    const ERR_POOL_ALREADY_EXIST = 101;
    /// When not exists on account
    const ERR_POOL_NOT_EXIST = 102;
    /// When not greater than zero;
    const ERR_MUST_BE_GREATER_THAN_ZERO = 103;
    /// When not exists on account
    const ERR_USERINFO_NOT_EXIST = 104;
    /// When insufficient balance
    const ERR_INSUFFICIENT_BALANCE = 105;

    const DEPLOYER_ADDRESS: address = @MasterChefDeployer;
    const RESOURCE_ACCOUNT_ADDRESS: address = @ResourceAccountDeployer;

    /// Store min/burn/freeze capabilities for reward token under user account
    struct Caps<phantom CoinType> has key {
        direct_mint: bool,
        mint: MintCapability<CoinType>,
        // freeze: FreezeCapability<CoinType>,
        burn: BurnCapability<CoinType>,
    }

    struct CoinMeta has copy, drop, store {
        type_info: TypeInfo,
        alloc_point: u64,
    }

    /// Store all admindata under masterchef
    struct MasterChefData has key, drop {
        // signer_cap: SignerCapability,
        admin_address: address,
        dev_address: address,
        dev_percent: u64,
        bonus_multiplier: u64,
        total_alloc_point: u64,
        per_second_reward: u128,
        start_timestamp: u64,
        last_timestamp_dev_withdraw: u64,
    }

    /// Store staked LP info under masterchef
    struct LPInfo has key {
        lp_list: vector<TypeInfo>
    }

    /// Store available pool info under masterchef
    struct PoolInfo<CoinType> has key, store {
        alloc_point: u64,
        acc_reward_per_share: u128,
        last_reward_timestamp: u64,
    }

    /// Store user info under user account
    struct UserInfo<CoinType> has key, copy, store {
        amount: u64,
        reward_debt: u128,
    }

    /// Test reward coin
    struct TestCoin {}

    public fun initialize_internal(account: &signer) {
        let (mint_cap, burn_cap) = coin::initialize<TestCoin>(
            account,
            string(b"TestCoin"),
            string(b"TC"),
            10,
            true,
        )
        let admin_addr = signer::address_of(account);
        let current_timestamp = timestamp::now_seconds();

        move_to(account, Caps<TestCoin>{
            direct_mint: true,
            mint: mint_cap,
            burn: burn_cap
        });
        move_to(account, MasterChefData{
            admin_address: admin_addr,
            dev_address: admin_addr,
            dev_percent: 10,
            bonus_multiplier: 10,
            total_alloc_point: 0,
            per_second_reward: 10000000,
            start_timestamp: current_timestamp,
            last_timestamp_dev_withdraw: current_timestamp,
        });
    }

/// functions list for getting info
    /// Get user deposit amount
    public fun get_user_info_amount<CoinType>(user_addr: address): u64 acquires UserInfo {
        assert(exists<UserInfo<CoinType>>(user_addr), ERR_USERINFO_NOT_EXIST);
        let existing_info = borrow_global<UserInfo<CoinType>>(user_addr);
        existing_info.amount
    }

    /// Get the pending reward token amount
    public fun get_pending_rewardtoken(account: address): u64 {}

/// functions list for only owner ///
    /// Add a new pool
    public entry fun add<CoinType>(account: &signer, alloc_point: u64) acquires PoolInfo {
        let admin_addr = signer::address_of(account);
        let masterchef_data = borrow_global_mut<MasterChefData>(admin_addr);

        assert(!exists<PoolInfo<CoinType>>(admin_addr), ERR_POOL_ALREADY_EXIST);

        let current_timestamp = timestamp::now_seconds();
        masterchef_data.total_alloc_point += alloc_point;
        move_to(account, PoolInfo<CoinType>{
            alloc_point: alloc_point,
            acc_reward_per_share: 0,
            last_reward_timestamp: current_timestamp,
        });
    }

    /// Set the existing pool
    public entry fun set<CoinType>(account: &signer, alloc_point: u64) acquires PoolInfo {
        let admin_addr = signer::address_of(account);
        let masterchef_data = borrow_global_mut<MasterChefData>(admin_addr);

        assert(exists<PoolInfo<CoinType>>(admin_addr), ERR_POOL_NOT_EXIST);

        let existing_pool = borrow_global_mut<PoolInfo<CoinType>>(admin_addr);
        masterchef_data.total_alloc_point = masterchef_data.total_alloc_point - existing_pool.alloc_point + alloc_point;
        existing_pool.alloc_point = alloc_point;
    }
    public entry fun mint_rwardtoken(account: &signer, amount: u64, to: address) {}

/// functions list for every user ///
    /// Deposit LP tokens to pool
    public entry fun deposit<CoinType>(account: &signer, amount_in: u64) acquires UserInfo {
        let coins_in = coin::withdraw<CoinType>(account, amount_in);
        let _amount_in = coin::value(&coins_in);
        assert(_amount_in > 0, ERR_MUST_BE_GREATER_THAN_ZERO);

        let pool_token_info = borrow_global_mut<Coin<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
        coin::merge(&mut pool_token_info, coins_in);

        let user_addr = signer::address_of(account);
        if (!exists<UserInfo<CoinType>>(user_addr)) {
            move_to(account, UserInfo<CoinType>{
                amount: _amount_in,
                reward_debt: 0,
            });
        } else {
            let existing_info = borrow_global_mut<UserInfo<CoinType>>(user_addr);
            existing_info.amount += _amount_in;
        }
    }

    /// Withdraw LP tokens from pool
    public entry fun withdraw<CoinType>(account: &signer, amount_out: u64) acquires UserInfo {
        let user_addr = signer::address_of(account);
        assert(exists<UserInfo<CoinType>>(user_addr), ERR_USERINFO_NOT_EXIST);

        let existing_info = borrow_global_mut<UserInfo<CoinType>>(user_addr);
        assert(existing_info.amount >= amount_out, ERR_INSUFFICIENT_BALANCE);

        if (amount_out > 0) {
            existing_info.amount -= amount_out;
            let pool_token_info = borrow_global_mut<Coin<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
            let coins_out = coin::extract(&mut pool_token_info, amount_out);
            coin::deposit<CoinType>(user_addr, coins_out);
        }
    }

    // public entry fun enter_staking(account: &signer, amount: u64) {}
    // public entry fun leave_staking(account: &signer, amount: u64) {}
    
    // Withdraw without caring about the rewards. EMERGENCY ONLY
    public entry fun emergency_withdraw<CoinType>(account: &signer) acquires UserInfo {
        let user_addr = signer::address_of(account);
        assert(exists<UserInfo<CoinType>>(user_addr), ERR_USERINFO_NOT_EXIST);

        let existing_info = borrow_global_mut<UserInfo<CoinType>>(user_addr);
        let amount_out = existing_info.amount;
        assert(amount_out > 0, ERR_MUST_BE_GREATER_THAN_ZERO);

        existing_info.amount = 0;
        let pool_token_info = borrow_global_mut<Coin<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
        let coins_out = coin::extract(&mut pool_token_info, amount_out);
        coin::deposit<CoinType>(user_addr, coins_out);
    }
}
