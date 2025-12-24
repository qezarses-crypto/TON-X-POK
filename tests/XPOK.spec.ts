import { Blockchain, printTransactionFees, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { Cell, fromNano, toNano } from '@ton/core';
import { XPOK } from '../build/XPOK/XPOK_XPOK';
import '@ton/test-utils';
import { StorageContract } from '../build/XPOK/XPOK_StorageContract';
import { RoundContract } from '../build/XPOK/XPOK_RoundContract';

describe('XPOK', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let pokJettonMaster: SandboxContract<TreasuryContract>;
    let pokJettonWallet: SandboxContract<TreasuryContract>;
    let marketMaker: SandboxContract<TreasuryContract>;
    let royaltyWallet: SandboxContract<TreasuryContract>;
    let player1: SandboxContract<TreasuryContract>;

    let xpok: SandboxContract<XPOK>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        deployer = await blockchain.treasury('deployer');
        pokJettonMaster = await blockchain.treasury('pokJettonMaster');
        pokJettonWallet = await blockchain.treasury('pokJettonWallet');
        marketMaker = await blockchain.treasury('marketMaker');
        royaltyWallet = await blockchain.treasury('royaltyWallet');
        player1 = await blockchain.treasury('player1');

        xpok = blockchain.openContract(
            await XPOK.fromInit(
                deployer.address,
                pokJettonMaster.address,
                marketMaker.address,
                royaltyWallet.address,
                1745899800n,
                1n,
                2n,
                3n,
                30000n,
            ),
        );

        const deployResult = await xpok.send(
            deployer.getSender(),
            {
                value: toNano('0.5'),
            },
            null,
        );

        const takeWalletAddress = await xpok.send(
            pokJettonMaster.getSender(),
            {
                value: toNano('0.05'),
            },
            {
                $$type: 'TakeWalletAddress',
                query_id: 0n,
                wallet_address: pokJettonWallet.address,
            },
        );

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: xpok.address,
            deploy: true,
            success: true,
        });
    });

    it.skip('should deploy', async () => {
        const ownerAddress = await xpok.getOwnerAddress();
        const pokJettonMasterAddress = await xpok.getPokJettonMaster();
        const marketMakerAddress = await xpok.getMarketMaker();
        const royaltyWalletAddress = await xpok.getRoyaltyWallet();
        const startedDate = await xpok.getStartedDate();
        const isLotteryStartedc = await xpok.getIsLotteryStarted();
        const jettonWalletAddress = await xpok.getPokJettonWallet();

        expect(jettonWalletAddress).toEqualAddress(pokJettonWallet.address);

        expect(ownerAddress).toEqualAddress(deployer.address);
        expect(pokJettonMasterAddress).toEqualAddress(pokJettonMaster.address);
        expect(marketMakerAddress).toEqualAddress(marketMaker.address);
        expect(royaltyWalletAddress).toEqualAddress(royaltyWallet.address);
        expect(startedDate).toEqual(1745899800n);
        expect(isLotteryStartedc).toBe(false);
    });

    it('should buy tickets', async () => {
        // initialize season at first
        const initSeason = await xpok.send(
            deployer.getSender(),
            {
                value: toNano('10.1'),
            },
            {
                $$type: 'InitializeSeason',
                pokAmount: 1000000000n,
            },
        );
        // printTransactionFees(initSeason.transactions);

        expect(await xpok.getIsLotteryStarted()).toBe(true);

        const buyTicketsResult = await xpok.send(
            player1.getSender(),
            {
                value: toNano('50.15'),
            },
            {
                $$type: 'BuyTickets',
                isNewUser: true,
            },
        );

        expect(buyTicketsResult.transactions).toHaveTransaction({
            from: player1.address,
            to: xpok.address,
            success: true,
        });
        printTransactionFees(buyTicketsResult.transactions);
        const ticketsSold = await xpok.getTicketsSold();
        expect(ticketsSold).toBe(250n);

        //check storage
        const storage = blockchain.openContract(await StorageContract.fromInit(xpok.address, player1.address));
        const participantAddress = await storage.getCheckParticipantAddress();
        expect(participantAddress).toEqualAddress(player1.address);
        const mapLen = await storage.getMapLen();
        expect(mapLen).toBe(1n);
        const storageBalanceBeforeWin = await storage.getBalance();
        console.log('Storage balance before win:', fromNano(storageBalanceBeforeWin));

        //emulate pok transfer notification to trigger win check
        const pokTransferNotificationResult = await xpok.send(
            pokJettonWallet.getSender(),
            {
                value: toNano('5.1'),
            },
            {
                $$type: 'JettonTransferNotification',
                queryId: 0n,
                sender: marketMaker.address,
                amount: 1000000000n,
                forwardPayload: Cell.EMPTY.asSlice(),
            },
        );
        //printTransactionFees(pokTransferNotificationResult.transactions);

        const currentRoundAddress = await xpok.getRoundContractAddress(1n, 1n);
        const round = blockchain.openContract(RoundContract.fromAddress(currentRoundAddress));
        //        const winnersCount = await round.getWinnersCount(); this is about jackpot winners
        //        expect(winnersCount).toBeGreaterThan(1n);
        const fund = await round.getPrizeFund();
        console.log('Fund', fromNano(fund));

        const sendWinTxResult = await xpok.send(
            player1.getSender(),
            {
                value: toNano('10.1'),
            },
            {
                $$type: 'Win',
            },
        );
        printTransactionFees(sendWinTxResult.transactions);

        //console.log('Round contract balance after pok transfer notification:', winnersCount);
        //try emergency withdraw
        /*const getWinTxResult = await xpok.send(
            player1.getSender(),
            {
                value: toNano('0.1'),
            },
            {
                $$type: 'GetWin',
            },
        );
        console.log('balance after win:', fromNano(await storage.getBalance()));
        printTransactionFees(getWinTxResult.transactions);
        expect(getWinTxResult.transactions).toHaveTransaction({
            from: player1.address,
            to: xpok.address,
            success: true,
        });

        const ticketsSoldAfterWithdraw = await xpok.getTicketsSold();
        expect(ticketsSoldAfterWithdraw).toBe(250n); // should be same as before*/
    });

    it('should buy tickets low', async () => {
        // initialize season at first
        const initSeason = await xpok.send(
            deployer.getSender(),
            {
                value: toNano('10.1'),
            },
            {
                $$type: 'InitializeSeason',
                pokAmount: 1000000000n,
            },
        );
        // printTransactionFees(initSeason.transactions);

        expect(await xpok.getIsLotteryStarted()).toBe(true);

        const buyTicketsResult = await xpok.send(
            player1.getSender(),
            {
                value: toNano('0.55'),
            },
            {
                $$type: 'BuyTickets',
                isNewUser: true,
            },
        );

        expect(buyTicketsResult.transactions).toHaveTransaction({
            from: player1.address,
            to: xpok.address,
            success: true,
        });
        printTransactionFees(buyTicketsResult.transactions);
        //const ticketsSold = await xpok.getTicketsSold();
        //expect(ticketsSold).toBe(250n);

        
    });
});
