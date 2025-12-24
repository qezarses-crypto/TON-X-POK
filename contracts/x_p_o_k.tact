// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/
import "./constants.tact";
import "./errors.tact";
import "./round_contract";
import "./storage_contract";
import "./messages";
import "./functions.tact";

contract XPOK {
    // адреса
    owner: Address; // адрес владельца
    marketMaker: Address; // адрес ММ
    pokJettonMasterAddress: Address; // адрес контракта-мастера POK 
    pokJettonWalletAddress: Address; // адрес контракта-кошелька POK для контракта-лотереи
    royaltyWallet: Address; // адрес роялти для вывода комиссии ?? с чего идет тогда комиссия

    additionalJettonWalletAddress: Address;
    additionalJettonMasterAddress: Address;

    // балансы
    pokBalance: Int as coins; // баланс POK с покупки билетов в последний день и транзакции ММ ??
    additionalPrize: Int as coins; // баланс дополнительного приза на каждый раунд (первое пополнение ММ POK, разделенное на количество дней лотереи), хранит сумму на 1 раунд
    tons: Int as coins; // баланс TON, отправляемых каждый день ММ, для последнего дня ?? джекпот ?? поменять название переменной на более явную
    workTon: Int as coins; // баланс "рабочих" тонов, которыми поплняет контракт владелец
    allPOKBalance: Int as coins; // баланс всех POK, которые приходят на контракт (ввиду остутствия встроенных методов их отслеживания)

    // изменяемые цены
    ticketPOKPrice: Int as coins; // цена билета в POK
    
    // дополнительные значения по переменной
    isLotteryStarted: Bool; // Флаг старта лотереи, на случай экстренной необходимости остановки лотереии ?? нужен или нет, мало весит, так как булево значение
    indexGame: Int as uint16; // Индекс (порядковый номер) игры (необходим для деплоя раундов и отслеживания последней 30 игры)
    indexLoop: Int as uint16;
    levelIndex: Int as uint8; // Индекс с которого стартует распределение основного приза (задается при деплое)
    winningProbability: Int as uint8; // Вероятность выигрыша в соотношении 1 к n

    // переменные по билетам
    ticketsSold: Int as uint32; // Общее количество проданных билетов
    ticketsSoldBefore: Int as uint32; // Количество проданных билетов на предыдущем раунде, ?? количество проданных билетов на текущем раунде вычисляется как разность общего количества и количества на предыдущем раунде
    winTickets: Int as uint32; // Количество выигрышных билетов
    maxTickets: Int as uint64; // Максимально количество билетов на раунд (задается при деплое)

    // даты
    startedDate: Int as uint32; // Стартовая дата лотереи, то есть дата начала каждого раунда
    lockEndDate: Int as uint32; // Дата окончания лока между одним запуском лотереи и следующим

    lastGameIndex: Int as uint16;

    tonBalance: Int as coins; // баланс тонов с покупки участниками билетов

    init(owner: Address,
        pokJettonMasterAddress: Address,
        marketMaker: Address,
        royaltyWallet: Address,
        startedDate: Int,
        levelIndex: Int,
        lastGameIndex: Int,
        winningProbability: Int,
        maxTickets: Int) {
        self.owner = owner;
        self.marketMaker = marketMaker;
        self.royaltyWallet = royaltyWallet;
        self.pokJettonMasterAddress = pokJettonMasterAddress;
        self.pokJettonWalletAddress = owner;
        self.pokBalance = 0;
        self.additionalPrize = 0;
        self.ticketPOKPrice = 1_500 * NANO_COINS_VALUES; // не задаем начальные значения цен нулевыми ??
        self.startedDate = startedDate;
        self.workTon = 0;

        self.isLotteryStarted = false;
        self.ticketsSold = 0;
        self.ticketsSoldBefore = 0;
        self.winTickets = 0;
        self.indexGame = 0;
        self.indexLoop = 0;
        self.tons = 0;
        self.tonBalance = 0;
        self.lockEndDate = 0;

        self.allPOKBalance = 0;
        self.levelIndex = levelIndex;
        self.lastGameIndex = lastGameIndex;
        self.winningProbability = winningProbability; // Коэффициент (отношение) выигрыша в формате "1 к X", для меньшего диапазона в рандоме ??

        self.maxTickets = maxTickets;

        self.additionalJettonWalletAddress = owner;
        self.additionalJettonMasterAddress = owner;

        message(MessageParameters{ 
            to: self.pokJettonMasterAddress,
            value: 0,
            mode: SendRemainingValue,
            body: ProvideWalletAddress{query_id: now(), owner_address: myAddress(), include_address: false}.toCell()
        });
    }

    receive(){}

    receive(msg: TakeWalletAddress) { 
        require(self.pokJettonWalletAddress != newAddress(0, 0), "Contract POK jetton wallet id cannot be zero"); 
        require(sender() == self.pokJettonMasterAddress, "Invalid jetton master POK sender"); 
        self.pokJettonWalletAddress = msg.wallet_address; 
        if (self.pokJettonWalletAddress == self.owner) { 
            message(MessageParameters{
                to: self.pokJettonMasterAddress, 
                value: 0, 
                mode: SendRemainingValue,
                body: ProvideWalletAddress{query_id: now(), owner_address: myAddress(), include_address: true}.toCell()});
        }        
    }

    receive(msg: AddAdditionalJettonData) {
        throwUnless(ErrorUnauthorized, sender() == self.owner);
        require(msg.newAdditionalJettonMasterAddress != self.pokJettonMasterAddress, "Additional jetton master address in message cannot be support master jetton");
        require(msg.newAdditionalJettonWalletAddress != self.pokJettonWalletAddress, "Additional jetton wallet address in mesage cannot be support jetton wallet");
        require(msg.newAdditionalJettonMasterAddress != newAddress(0, 0), "Additional jetton master address in message cannot be zero");
        require(msg.newAdditionalJettonWalletAddress != newAddress(0, 0), "Additional jetton wallet address in mesage cannot be zero");
        require(self.additionalJettonMasterAddress != newAddress(0, 0), "Additional jetton master address cannot be zero"); 
        require(self.additionalJettonWalletAddress != newAddress(0, 0), "Additional jetton wallet address cannot be zero");
        self.additionalJettonMasterAddress = msg.newAdditionalJettonMasterAddress;
        self.additionalJettonWalletAddress = msg.newAdditionalJettonWalletAddress;
        transferTokensTo(self.additionalJettonWalletAddress, sender(), msg.amount, "Send other jettons to owner");
    }

    receive(msg: ChangePrice) { 
        throwUnless(ErrorUnauthorized, sender() == self.owner);
        throwUnless(ErrorInvalidTicketPrice, msg.newticketPOKPrice != 0);
        if (msg.newticketPOKPrice != 0) {
            self.ticketPOKPrice = msg.newticketPOKPrice * NANO_COINS_VALUES;
        }
        cashback(sender());
    }

    receive(msg: StartStopLottery) {
        throwUnless(ErrorUnauthorized, sender() == self.owner);
        self.isLotteryStarted = msg.isLotteryStarted;
        cashback(sender());
    }

    receive(msg: NewStartDate) { 
        throwUnless(ErrorUnauthorized, sender() == self.owner);
        self.startedDate = msg.newStartDate;
        cashback(sender());
    }

    receive(msg: WithdrawAllTons) { 
        throwUnless(ErrorUnauthorized, sender() == self.owner);
        throwUnless(ErrorLockNotOver, now() > self.lockEndDate);
        message(MessageParameters{
            to: self.owner,
            value: 0,
            bounce: false,
            mode: SendRemainingBalance,
            body: "Transfer TON balance".asComment()
        });
    }

    receive(msg: NewOwner) {
        throwUnless(ErrorUnauthorized, sender() == self.owner);
        require(msg.newOwnerAddress != newAddress(0, 0) && msg.newOwnerAddress != self.owner, "New owner address cannot be null or equal to current owner");
        self.owner = msg.newOwnerAddress;
        cashback(sender());
    }

    receive(msg: ChangeMarketMaker) {
        throwUnless(ErrorUnauthorized, sender() == self.owner);
        require(msg.newMarketMakerAddress != newAddress(0, 0) && msg.newMarketMakerAddress != self.marketMaker, "New owner address cannot be null or equal to current market maker");
        self.marketMaker = msg.newMarketMakerAddress;
        cashback(sender());
    }

    receive(msg: ChangeRoyalty) {
        throwUnless(ErrorUnauthorized, sender() == self.owner);
        require(msg.newRoyaltyAddress != newAddress(0, 0) && msg.newRoyaltyAddress != self.royaltyWallet, "New owner address cannot be null or equal to current royalty wallet");
        self.royaltyWallet = msg.newRoyaltyAddress;
        cashback(sender());
    }

    receive(msg: WithdrawFromRound) {
        throwUnless(ErrorUnauthorized, sender() == self.owner);
        let init: StateInit = initOf RoundContract(myAddress(), msg.roundId);
        sendMsgWithReserve(contractAddress(init), context().value, msg.toCell());
    }

    receive(msg: ChangeLastGameIndex) {
        throwUnless(ErrorUnauthorized, sender() == self.owner);
        throwUnless(ErrorInvalidLastGameIndexRange, msg.newLastGameIndex > self.indexGame && msg.newLastGameIndex <= 31);
        self.lastGameIndex = msg.newLastGameIndex;
        cashback(sender());
    }

    receive(msg: ExtendLockTimeByDays) {
        throwUnless(ErrorUnauthorized, sender() == self.owner);
        throwUnless(ErrorInvalidAdditionalDaysRange, msg.additionalDays > 0 && msg.additionalDays <= 31);
        self.lockEndDate += msg.additionalDays * 86_400;
        cashback(sender());
    }

    receive(msg: InitializeSeason) {
        throwUnless(ErrorUnauthorized, sender() == self.owner);
        throwUnless(ErrorNotEnoughTonsForCommission, context().value >= COMMISSION * 2);
        if (self.indexGame == 0) {
            self.additionalPrize = 0;//msg.amount / (self.lastGameIndex - 1); 
            self.allPOKBalance += msg.pokAmount;
            self.indexLoop += 1;
            self.indexGame += 1;
            self.isLotteryStarted = true;
            let roundIndex: Int = self.indexLoop * 1000 + self.indexGame;
            let toLeaveOnBalance = (myBalance() - context().value) + myStorageDue();
            nativeReserve(toLeaveOnBalance, ReserveAtMost);
            deploy(DeployParameters{
                init: initOf RoundContract(myAddress(), roundIndex),
                body: StartValues{
                        levelIndex: self.levelIndex,
                        winningProbability: self.winningProbability
                        }.toCell(),
                mode:  SendRemainingBalance | SendIgnoreErrors,
                value: 0
            });
        }
    }

    receive(msg: BuyTickets) { 
        let ctx: Context = context();
        try {
            throwUnless(ErrorLotteryNotStarted, self.isLotteryStarted == true);
            throwUnless(ErrorLastDayUnavailable, self.indexGame < self.lastGameIndex);
            throwUnless(ErrorNotEnoughTonsToBuyTicket, ctx.value >= TICKET_TON_PRICE + COMMISSION * 2);
            throwUnless(ErrorMaxTicketsReached, self.ticketsSold - self.ticketsSoldBefore < self.maxTickets);
            let tickets: Int = (ctx.value - COMMISSION * 3) / TICKET_TON_PRICE;
            throwUnless(MaxTicketsCount, tickets < 251);
            let allTicketsPrice = tickets * TICKET_TON_PRICE;
            let winTickets: Int = self.checkWinTickets(tickets);

            let toLeaveOnBalance = (myBalance() - (ctx.value - allTicketsPrice)) + myStorageDue();
            nativeReserve(toLeaveOnBalance, ReserveAtMost);
            if(winTickets > 0) {
                
                let index: Int = self.indexLoop * 1000 + self.indexGame;
                if (msg.isNewUser) {
                    deploy(DeployParameters{
                        init: initOf StorageContract(myAddress(), sender()),
                        body: Winners{indexGame: index, winTickets: winTickets}.toCell(),
                        mode: SendIgnoreErrors| SendRemainingBalance,
                        value: 0
                    });                       
                }else{
                    message(MessageParameters{
                        to: contractAddress(initOf StorageContract(myAddress(), sender())),
                        value: 0,
                        mode: SendIgnoreErrors | SendRemainingBalance,
                        body: Winners{indexGame: index, winTickets: winTickets}.toCell(),
                    });
                }      
            }else{
                message(MessageParameters{
                    to: sender(),
                    value: 0,
                    bounce: false,
                    mode: SendRemainingBalance,
                    body: "Your change".asComment()
                });
            }
            self.tonBalance += allTicketsPrice;
            self.ticketsSold += tickets;
        } catch (error) {
            let errorComment: StringBuilder = beginString();
            errorComment.append("Something went wrong (");
            errorComment.append(error.toString());
            errorComment.append(")");
            self.notify(errorComment.toString().asComment());
        }
    }

    receive(msg: Win) {
        //отправляется юзером для получения выигрыша
        try {
            throwUnless(ErrorNotEnoughTons, context().value >= COMMISSION * 3);
            throwUnless(ErrorFirstRoundNotOver, self.indexGame > 1);
            let init: StateInit = initOf StorageContract(myAddress(), sender());
            sendMsgWithReserve(contractAddress(init), context().value, GetFullWin{}.toCell());
        } catch (_) {
            self.notify("Not enough TONs to cover commission or the first round is not over yet".asComment());
        }
    }

    receive(msg: GetWin) {
        throwUnless(ErrorNotEnoughTons, context().value >= COMMISSION);
        let init: StateInit = initOf StorageContract(myAddress(), sender());
        sendMsgWithReserve(contractAddress(init), context().value, msg.toCell());
    }

    receive(msg: JettonTransferNotification) {
        let ctx: Context = context();
        throwUnless(ErrorNotEnoughTonsForStorageDeploy, ctx.value >= COMMISSION * 3);
        throwUnless(ErrorOnlyPOKCanbeUsed, sender() == self.pokJettonWalletAddress);
        try {
            if (self.indexGame >= 1) {
                if (msg.sender == self.marketMaker && self.indexGame < self.lastGameIndex) { // сделать отправку сообщения на контракт с ПОК для закупки (то есть отправляем все TON разными сообщениями и получаем ПОК)
                    //тут надо посчитать комиссии, это отправляет маркетмейкер если не последний раунд
                    throwUnless(ErrorLotteryNotStarted, self.isLotteryStarted == true);
                    // цена ПОК в каких-то диапазонах
                    self.allPOKBalance += msg.amount;
                    sendTon(msg.sender, self.tonBalance, "Buying POK for TON");
                    self.tonBalance = 0;
                    self.tons += ctx.value - COMMISSION;
                    self.sendRoundContractGetWinMsg(msg.amount, self.additionalPrize);
                    self.indexGame += 1;
                    self.deployRound();
                } else if (msg.sender == self.marketMaker && self.indexGame == self.lastGameIndex) {
                    throwUnless(ErrorLotteryNotStarted, self.isLotteryStarted == true);
                    let royaltyProfit: Int = msg.amount / 10;
                    transferTokensTo(self.pokJettonWalletAddress, self.royaltyWallet, royaltyProfit, "Royalty profit");
                    self.allPOKBalance += msg.amount - royaltyProfit;
                    self.sendRoundContractGetWinMsg(self.pokBalance, msg.amount - royaltyProfit);
                    sendTon(msg.sender, self.tons, "Buying POK for TON");
                    self.tons = 0;
                    if(self.lockEndDate < now() + TWO_DAYS){
                        self.lockEndDate = now() + TWO_DAYS;
                    }
                    self.isLotteryStarted = false;
                    self.indexGame = 0;
                } else {
                    require(self.indexGame == self.lastGameIndex, "Available only on the last day of the lottery");
                    require(self.isLotteryStarted == true, "Lottery is not started");
                    require(msg.amount >= self.ticketPOKPrice, "Not enough POK to buy a ticket");
                    require(self.ticketsSold - self.ticketsSoldBefore < self.maxTickets, "Max tickets limit reached");
                    let tickets: Int = msg.amount / self.ticketPOKPrice;
                    throwUnless(MaxTicketsCount, tickets < 251);
                    let winTickets: Int = self.checkWinTickets(tickets);

                    if (winTickets > 0) {
                        let index: Int = self.indexLoop * 1000 + self.indexGame;
                        let toLeaveOnBalance = (myBalance() - ctx.value) + myStorageDue();
                        nativeReserve(toLeaveOnBalance, ReserveAtMost);
                        deploy(DeployParameters{
                            init: initOf StorageContract(myAddress(), sender()),
                            body: Winners{indexGame: index, winTickets: winTickets}.toCell(),
                            mode: SendIgnoreErrors| SendRemainingBalance,
                            value: 0
                        });  
                    } 
                    self.ticketsSold += tickets;
                    self.pokBalance += msg.amount;
                    self.allPOKBalance += msg.amount;
                }
            }      
        } catch (error) {
            let errorComment: StringBuilder = beginString();
            errorComment.append("Something went wrong (");
            errorComment.append(error.toString());
            errorComment.append(")");
            transferTokensTo(self.pokJettonWalletAddress, msg.sender, msg.amount, errorComment.toString());
        }        
    }

    receive(msg: WTHPOKDebug) {
        throwUnless(ErrorUnauthorized, sender() == self.owner);
        throwUnless(ErrorLockNotOver, now() > self.lockEndDate);
        let pokAmount: Int = msg.pokAmount != null ? msg.pokAmount!! : self.allPOKBalance;
        transferTokensTo(self.pokJettonWalletAddress, sender(), pokAmount, "Transfer all POKs");
        self.allPOKBalance = 0;
        self.pokBalance = 0;
    }

    receive(msg: WTHCoinsBalances) {
        throwUnless(ErrorUnauthorized, sender() == self.owner);
        throwUnless(ErrorLockNotOver, now() > self.lockEndDate);
        transferTokensTo(self.pokJettonWalletAddress, sender(), self.allPOKBalance, "Transfer POKs to owner");
        self.pokBalance = 0;
        self.additionalPrize = 0;
        self.workTon = COMMISSION;
        self.isLotteryStarted = false;
        self.ticketsSold = 0;
        self.ticketsSoldBefore = 0;
        self.winTickets = 0;
        self.indexGame = 0;
        self.tons = 0;
        self.lockEndDate = 0;
        self.allPOKBalance = 0;
        self.pokBalance = 0;
    }

    receive(msg: FullWin) {
        throwUnless(ErrorUnauthorized, sender()==contractAddress(initOf StorageContract(myAddress(), msg.participant)));
        try {
            throwUnless(ErrorNoTickets, msg.amount != 0);
            transferTokensTo(self.pokJettonWalletAddress, msg.participant, msg.amount, "Your full win");
            self.allPOKBalance -= msg.amount;
        } catch (error) {
            sendComment(msg.participant, "You have no tickets!");
        }
    }

    fun sendRoundContractGetWinMsg(prize: Int, addPrize: Int) {
        let roundIndex: Int = self.indexLoop * 1000 + self.indexGame;
        let init: StateInit = initOf RoundContract(myAddress(), roundIndex);
        let ticketsSoldPerRound: Int = self.ticketsSold - self.ticketsSoldBefore;
        let sendValue: Int = COMMISSION * 3;
        message(MessageParameters{
            to: contractAddress(init),
            body: PrizePoolForRound{amount: prize, addPrize: addPrize, ticketsSold: ticketsSoldPerRound, ticketsWin: self.winTickets}.toCell(),
            value: sendValue,
            mode: SendIgnoreErrors | SendPayFwdFeesSeparately,
        });
        self.ticketsSoldBefore = self.ticketsSold;
        self.winTickets = 0;
    }

    fun checkWinTickets(tickets: Int): Int {
        if (tickets == 0) {
            return 0;
        }
        let winTickets: Int = 0;
        repeat (tickets) {
            let winFlag: Bool = random(1, self.winningProbability + 1) == 1 ? true : false;
            if (winFlag) {
                winTickets += 1;
            }
        }
        self.winTickets += winTickets;
        return winTickets;
    }

    inline fun deployRound(){
        let roundIndex: Int = self.indexLoop * 1000 + self.indexGame;
        let init: StateInit = initOf RoundContract(myAddress(), roundIndex);
        deploy(DeployParameters{
            init: init,
            body: StartValues{
                levelIndex: self.levelIndex,
                winningProbability: self.winningProbability
            }.toCell(),
            mode: SendIgnoreErrors | SendPayFwdFeesSeparately,
            value: COMMISSION
        });
    }

    get fun balance(): Int {
        return myBalance();
    }

    get fun owner_address(): Address {
        return self.owner;
    }

    get fun contract_address(): Address {
        return myAddress();
    }

    get fun round_contract_address(indexLoop: Int, indexGame: Int): Address {
        let roundIndex: Int = indexLoop * 1000 + indexGame;
        let init: StateInit = initOf RoundContract(myAddress(), roundIndex);
        return contractAddress(init);
    }

    get fun storage_address(participant: Address): Address {
        let init: StateInit = initOf StorageContract(myAddress(), participant);
        return contractAddress(init);
    }

    get fun market_maker(): Address {
        return self.marketMaker;
    }

    get fun pok_jetton_master(): Address {
        return self.pokJettonMasterAddress;
    }

    get fun pok_jetton_wallet(): Address {
        return self.pokJettonWalletAddress;
    }

    get fun royalty_wallet(): Address {
        return self.royaltyWallet;
    }

    get fun add_jetton_wallet(): Address {
        return self.additionalJettonWalletAddress;
    }

    get fun add_jetton_master(): Address {
        return self.additionalJettonMasterAddress;
    }

    get fun level_index(): Int {
        return self.levelIndex;
    }

    get fun loop_index(): Int {
        return self.indexLoop;
    }

    get fun last_game_index(): Int {
        return self.lastGameIndex;
    }

    get fun winning_probability(): Int {
        return self.winningProbability;
    }

    get fun max_tickets(): Int {
        return self.maxTickets;
    }

    get fun pok_balance(): Int {
        return self.pokBalance / NANO_COINS_VALUES;
    }

    get fun ticket_pok_price(): Int {
        return self.ticketPOKPrice / NANO_COINS_VALUES;
    }

    get fun ticket_ton_price(): Int {
        return TICKET_TON_PRICE / NANO_COINS_VALUES;
    }

    get fun commission(): Int {
        return COMMISSION;
    }

    get fun additional_prize(): Int {
        return self.additionalPrize;
    }

    get fun is_lottery_started(): Bool {
        return self.isLotteryStarted;
    }

    get fun tickets_sold(): Int {
        return self.ticketsSold - self.ticketsSoldBefore;
    }

    get fun tickets_sold_total(): Int {
        return self.ticketsSold;
    }

    get fun tickets_sold_before(): Int {
        return self.ticketsSoldBefore;
    }

    get fun win_tickets(): Int {
        return self.winTickets;
    }

    get fun index_game(): Int {
        return self.indexGame;
    }

    get fun started_date(): Int {
        return self.startedDate;
    }

    get fun tons_for_last_day(): Int {
        return self.tons;
    }

    get fun lock_end_date(): Int {
        return self.lockEndDate;
    }

    get fun work_ton(): Int {
        return self.workTon;
    }

    get fun all_pok_balance(): Int {
        return self.allPOKBalance;
    }

    get fun ticket_for_ton(ton: Int): Int {
        return ton / TICKET_TON_PRICE;
    }

    get fun ton_balance(): Int {
        return self.tonBalance / NANO_COINS_VALUES;
    }

    get fun ticket_for_pok(pok: Int): Int {
        return (pok * NANO_COINS_VALUES) / self.ticketPOKPrice;
    }

    get fun win_commission(numRound: Int): Int {
        return (numRound * (COMMISSION * 3) + COMMISSION);
    }

    get fun owner(): Address {
        return self.owner;
    }
}