# ☀️ Pay-as-you-go Solar Access Contract

A decentralized smart contract enabling pay-per-use solar energy access on the Stacks blockchain.

## 🌟 Features

- **Solar System Registration**: Register solar panels with location, capacity, and pricing
- **User Account Management**: Create accounts and deposit funds for energy purchases
- **Pay-per-use Energy**: Purchase specific amounts of energy (kWh) from solar systems
- **Real-time Access Control**: Automated access validation based on payment status
- **Earnings Withdrawal**: Solar system owners can withdraw accumulated payments
- **System Management**: Control system status and track energy generation

## 🚀 Quick Start

### For Solar System Owners

1. **Register your solar system**:
   ```clarity
   (contract-call? .contract register-solar-system "New York, USA" u5000 u50)
   ```
   - Location: "New York, USA"
   - Capacity: 5000 kWh
   - Rate: 50 STX per kWh

2. **Update energy generation**:
   ```clarity
   (contract-call? .contract update-energy-generation u1 u100)
   ```

3. **Withdraw earnings**:
   ```clarity
   (contract-call? .contract withdraw-earnings u1 u1000)
   ```

### For Energy Consumers

1. **Register as a user**:
   ```clarity
   (contract-call? .contract register-user)
   ```

2. **Deposit funds**:
   ```clarity
   (contract-call? .contract deposit-funds u5000)
   ```

3. **Purchase energy**:
   ```clarity
   (contract-call? .contract pay-for-energy u1 u10)
   ```
   - System ID: 1
   - Energy: 10 kWh

## 📋 Contract Functions

### Public Functions

| Function | Description |
|----------|-------------|
| `register-solar-system` | Register a new solar system |
| `register-user` | Create a user account |
| `deposit-funds` | Add STX to user balance |
| `pay-for-energy` | Purchase energy from a system |
| `withdraw-earnings` | System owners withdraw payments |
| `update-system-status` | Enable/disable solar systems |
| `update-energy-generation` | Record energy production |
| `emergency-shutdown` | Admin function to disable systems |
| `update-contract-fee` | Admin function to set fees |

### Read-only Functions

| Function | Description |
|----------|-------------|
| `get-system-info` | Get solar system details |
| `get-user-account` | Get user account information |
| `get-user-access` | Check user's access to a system |
| `get-payment-info` | Get payment transaction details |
| `calculate-energy-cost` | Calculate cost for energy amount |
| `check-access-status` | Verify current access status |
| `get-user-balance` | Get user's current balance |
| `get-system-earnings` | Get system's total earnings |

## 💡 How It Works

1. **Solar Registration**: Owners register their solar systems with capacity and pricing
2. **User Onboarding**: Consumers create accounts and deposit STX tokens
3. **Energy Purchase**: Users pay for specific energy amounts from available systems
4. **Access Control**: Contract automatically manages access based on payments
5. **Payment Flow**: Funds transfer from consumers to system owners
6. **Usage Tracking**: All energy consumption and payments are recorded

## 🔧 Access Control

- Access expires after 144 blocks (~24 hours) from last payment
- Users must have sufficient balance for energy purchases
- Only system owners can manage their systems
- Contract owner has emergency shutdown capabilities

## 📊 Data Structures

- **Solar Systems**: Store owner, location, capacity, rates, and status
- **User Accounts**: Track balance, usage history, and system access
- **System Access**: Monitor user permissions and payment history
- **Payment History**: Record all energy purchases and transactions

## 🏗️ Development

### Prerequisites
- [Clarinet](https://docs.hiro.so/stacks/clarinet)
- Node.js for testing

### Commands
```bash
# Check contract syntax
clarinet check

# Run tests
npm test

# Deploy locally
clarinet integrate
```

## 🛡️ Security Features

- Owner-only functions for system management
- Balance validation before energy purchases
- Access expiration to prevent unauthorized usage
- Emergency shutdown for critical situations

## 📈 Use Cases

- **Distributed Solar Networks**: Enable community solar sharing
- **Energy Marketplace**: Create competitive energy pricing
- **Micro-transactions**: Pay for exact energy consumption
- **Green Energy Incentives**: Reward renewable energy adoption
