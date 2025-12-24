import { Address, toNano, beginCell } from '@ton/core';
import { NetworkProvider } from '@ton/blueprint';
import { CONTRACTADDRESS } from './!YOURCONTRACTADDRESS';

export async function run(provider: NetworkProvider) {
    const jettonWalletAddress = Address.parseRaw('0:b228b6c612aadd7c6af59e2284645040d2c030d3c95d5991091a5f99eb0a79a4');
    const contractAddress = Address.parse(CONTRACTADDRESS); 
    const sender = Address.parse("UQAIzXA4iuqWwozllUQ1-fD_UIaCsdxhIkN5vDMza6KX2yZy");

    const comment = 'Transfer main jetton from MM';
    
    const body = beginCell().storeUint(0xf8a7ea5, 32).storeInt(1735144534, 64).storeCoins(toNano('1000')).storeAddress(contractAddress).storeAddress(sender).storeBit(0).storeCoins(toNano('0.2')).storeBit(1).storeRef(beginCell().storeUint(0x00000000, 32).storeStringTail(comment).endCell()).endCell();


    await provider.sender().send({
        to: jettonWalletAddress,
        value: toNano('1'),
        bounce: true,
        body: body,
    });

    console.log('Jettons sent to address successfully.');
}