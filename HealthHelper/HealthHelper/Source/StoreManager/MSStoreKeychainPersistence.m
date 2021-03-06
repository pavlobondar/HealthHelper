//
//  MSStoreKeychainPersistence.m
//  HealthHelper
//
//  Created by Maksym Savisko on 4/10/17.
//  Copyright © 2017 Maksym Savisko. All rights reserved.
//

#import "MSStoreKeychainPersistence.h"
@import Security;

NSString* const RMStoreTransactionsKeychainKey = @"RMStoreTransactions";

#pragma mark - Keychain

NSMutableDictionary* RMKeychainGetSearchDictionary(NSString *key)
{
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    dictionary[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    
    NSData *encodedIdentifier = [key dataUsingEncoding:NSUTF8StringEncoding];
    
    dictionary[(__bridge id)kSecAttrGeneric] = encodedIdentifier;
    dictionary[(__bridge id)kSecAttrAccount] = encodedIdentifier;
    
    NSString *serviceName = [NSBundle mainBundle].bundleIdentifier;
    dictionary[(__bridge id)kSecAttrService] = serviceName;
    
    return dictionary;
}

void RMKeychainSetValue(NSData *value, NSString *key)
{
    NSMutableDictionary *searchDictionary = RMKeychainGetSearchDictionary(key);
    OSStatus status = errSecSuccess;
    CFTypeRef ignore;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)searchDictionary, &ignore) == errSecSuccess)
    { // Update
        if (!value)
        {
            status = SecItemDelete((__bridge CFDictionaryRef)searchDictionary);
        } else {
            NSMutableDictionary *updateDictionary = [NSMutableDictionary dictionary];
            updateDictionary[(__bridge id)kSecValueData] = value;
            status = SecItemUpdate((__bridge CFDictionaryRef)searchDictionary, (__bridge CFDictionaryRef)updateDictionary);
        }
    }
    else if (value)
    { // Add
        searchDictionary[(__bridge id)kSecValueData] = value;
        status = SecItemAdd((__bridge CFDictionaryRef)searchDictionary, NULL);
    }
    if (status != errSecSuccess)
    {
        NSLog(@"RMStoreKeychainPersistence: failed to set key %@ with error %ld.", key, (long)status);
    }
}

NSData* RMKeychainGetValue(NSString *key)
{
    NSMutableDictionary *searchDictionary = RMKeychainGetSearchDictionary(key);
    searchDictionary[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    searchDictionary[(__bridge id)kSecReturnData] = (id)kCFBooleanTrue;
    
    CFDataRef value = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)searchDictionary, (CFTypeRef *)&value);
    if (status != errSecSuccess && status != errSecItemNotFound)
    {
        NSLog(@"RMStoreKeychainPersistence: failed to get key %@ with error %ld.", key, (long)status);
    }
    return (__bridge NSData*)value;
}

@implementation MSStoreKeychainPersistence {
    NSDictionary *_transactionsDictionary;
}

#pragma mark - RMStoreTransactionPersistor

- (void)persistTransaction:(SKPaymentTransaction*)paymentTransaction
{
    SKPayment *payment = paymentTransaction.payment;
    NSString *productIdentifier = payment.productIdentifier;
    NSDictionary *transactions = [self transactionsDictionary];
    NSInteger count = [transactions[productIdentifier] integerValue];
    count++;
    NSMutableDictionary *updatedTransactions = [NSMutableDictionary dictionaryWithDictionary:transactions];
    updatedTransactions[productIdentifier] = @(count);
    [self setTransactionsDictionary:updatedTransactions];
}

#pragma mark - Public

- (void)removeTransactions
{
    [self setTransactionsDictionary:nil];
}

- (BOOL)consumeProductOfIdentifier:(NSString*)productIdentifier
{
    NSDictionary *transactions = [self transactionsDictionary];
    NSInteger count = [transactions[productIdentifier] integerValue];
    if (count > 0)
    {
        count--;
        NSMutableDictionary *updatedTransactions = [NSMutableDictionary dictionaryWithDictionary:transactions];
        updatedTransactions[productIdentifier] = @(count);
        [self setTransactionsDictionary:updatedTransactions];
        return YES;
    } else {
        return NO;
    }
}

- (NSInteger)countProductOfdentifier:(NSString*)productIdentifier
{
    NSDictionary *transactions = [self transactionsDictionary];
    NSInteger count = [transactions[productIdentifier] integerValue];
    return count;
}

- (BOOL)isPurchasedProductOfIdentifier:(NSString*)productIdentifier
{
    NSDictionary *transactions = [self transactionsDictionary];
    return transactions[productIdentifier] != nil;
}

- (NSSet*)purchasedProductIdentifiers
{
    NSDictionary *transactions = [self transactionsDictionary];
    NSArray *productIdentifiers = transactions.allKeys;
    return [NSSet setWithArray:productIdentifiers];
}

#pragma mark - Private

- (NSDictionary*)transactionsDictionary
{
    if (!_transactionsDictionary)
    { // Reading the keychain is slow so we cache its values in memory
        NSData *data = RMKeychainGetValue(RMStoreTransactionsKeychainKey);
        NSDictionary *transactions = @{};
        if (data)
        {
            NSError *error;
            transactions = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            if (!transactions)
            {
                NSLog(@"RMStoreKeychainPersistence: failed to read JSON data with error %@", error);
            }
        }
        _transactionsDictionary = transactions;
    }
    return _transactionsDictionary;
    
}

- (void)setTransactionsDictionary:(NSDictionary*)dictionary
{
    _transactionsDictionary = dictionary;
    NSData *data = nil;
    if (dictionary)
    {
        NSError *error;
        data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:&error];
        if (!data)
        {
            NSLog(@"RMStoreKeychainPersistence: failed to write JSON data with error %@", error);
        }
    }
    RMKeychainSetValue(data, RMStoreTransactionsKeychainKey);
}

@end

