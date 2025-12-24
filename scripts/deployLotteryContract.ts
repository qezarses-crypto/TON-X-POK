import { Address, toNano } from '@ton/core';
import { NetworkProvider } from '@ton/blueprint';
import { XPOK } from '../build/XPOK/XPOK_XPOK';

export async function run(provider: NetworkProvider) {
    const owner = Address.parse('UQAIzXA4iuqWwozllUQ1-fD_UIaCsdxhIkN5vDMza6KX2yZy');
    const pokJettonMasterAddress = Address.parse('EQBp6FAkDdHD_lLKUBI-J-Et5zQeyJlixc6f3iKHBie85Fd-');
    const MarketMakerAddress = Address.parse('UQAIzXA4iuqWwozllUQ1-fD_UIaCsdxhIkN5vDMza6KX2yZy');
    const RoyaltyWalletAddress = Address.parse('UQAP3YoWUpwXIZBCMPExVtwVLEazA37etHFkuspUMCMIOTjl');
    const StartedDate = 1766582023n; // нужно передавать значение старта первой лотереи
    const LevelIndex = 2n;
    const LastGameIndex = 5n;
    const WinningProbability = 3n; // 1 к n
    const MaxTickets = 30000n;

    const xpok = provider.open(
        await XPOK.fromInit(
            owner,
            pokJettonMasterAddress,
            MarketMakerAddress,
            RoyaltyWalletAddress,
            StartedDate,
            LevelIndex,
            LastGameIndex,
            WinningProbability,
            MaxTickets,
        ),
    );

    await xpok.send(
        provider.sender(),
        {
            value: toNano('0.1'),
        },
        null,
    );

    await provider.waitForDeploy(xpok.address);

    console.log(await xpok.getOwnerAddress());
    console.log(await xpok.getPokJettonMaster());
    console.log(await xpok.getMarketMaker());
    console.log(await xpok.getRoyaltyWallet());
    console.log(await xpok.getStartedDate());

    // run methods on `XPOK`
}
