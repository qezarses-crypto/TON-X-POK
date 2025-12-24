import { Address, toNano } from '@ton/core';
import { XPOK } from '../build/XPOK/XPOK_XPOK';
import { NetworkProvider } from '@ton/blueprint';
import { CONTRACTADDRESS } from './!YOURCONTRACTADDRESS';

export async function run(provider: NetworkProvider) {
    const contractAddress = Address.parse(CONTRACTADDRESS); 
    
    const superContract = provider.open(
        XPOK.fromAddress(contractAddress)
    );
    
    await superContract.send(
        provider.sender(),
        {
            value: toNano('0.1'), 
        },
        {
            $$type: 'InitializeSeason',
            pokAmount: 0n,
        }
    );
}