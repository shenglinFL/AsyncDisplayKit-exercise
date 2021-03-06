//
//  NSObject+DLNIntrospection.m
//  DLNFoundation
//
//  Created by Linzh on 1/13/16.
//  Copyright © 2016 Daniel Lin. All rights reserved.
//
#ifdef DEBUG
#import "NSObject+DLNIntrospection.h"
#import <objc/runtime.h>

@interface NSString (DLNIntrospection)

+ (NSString *)decodeType:(const char *)cString;

@end

@implementation NSString (DLNIntrospection)

//https://developer.apple.com/library/mac/#documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
+ (NSString *)decodeType:(const char *)cString {
    if (!strcmp(cString, @encode(id))) return @"id";
    if (!strcmp(cString, @encode(void))) return @"void";
    if (!strcmp(cString, @encode(float))) return @"float";
    if (!strcmp(cString, @encode(int))) return @"int";
    if (!strcmp(cString, @encode(BOOL))) return @"BOOL";
    if (!strcmp(cString, @encode(char *))) return @"char *";
    if (!strcmp(cString, @encode(double))) return @"double";
    if (!strcmp(cString, @encode(Class))) return @"class";
    if (!strcmp(cString, @encode(SEL))) return @"SEL";
    if (!strcmp(cString, @encode(unsigned int))) return @"unsigned int";
    
    //@TODO: do handle bitmasks
    NSString *result = [NSString stringWithCString:cString encoding:NSUTF8StringEncoding];
    if ([[result substringToIndex:1] isEqualToString:@"@"] && [result rangeOfString:@"?"].location == NSNotFound) {
        result = [[result substringWithRange:NSMakeRange(2, result.length - 3)] stringByAppendingString:@"*"];
    } else
        if ([[result substringToIndex:1] isEqualToString:@"^"]) {
            result = [NSString stringWithFormat:@"%@ *",
                      [NSString decodeType:[[result substringFromIndex:1] cStringUsingEncoding:NSUTF8StringEncoding]]];
        }
    return result;
}

@end

static void getSuper(Class class, NSMutableString *result) {
    [result appendFormat:@" -> %@", NSStringFromClass(class)];
    if ([class superclass]) { getSuper([class superclass], result); }
}

@implementation NSObject (DLNIntrospection)

#pragma mark - Public
+ (NSArray *)dln_classes {
    unsigned int classesCount;
    Class *classes = objc_copyClassList(&classesCount);
    NSMutableArray *result = [NSMutableArray array];
    for (int i = 0 ; i < classesCount; i++) {
        [result addObject:NSStringFromClass(classes[i])];
    }
    free(classes);
    return [result sortedArrayUsingSelector:@selector(compare:)];
}

+ (NSArray *)dln_classMethods {
    return [self methodsForClass:object_getClass([self class]) typeFormat:@"+"];
}

+ (NSArray *)dln_instanceMethods {
    return [self methodsForClass:[self class] typeFormat:@"-"];
}

+ (NSArray *)dln_properties {
    unsigned int outCount;
    objc_property_t *properties = class_copyPropertyList([self class], &outCount);
    NSMutableArray *result = [NSMutableArray array];
    for (int i = 0; i < outCount; i++) {
        [result addObject:[self formattedPropery:properties[i]]];
    }
    free(properties);
    return result.count ? [result copy] : nil;
}

+ (NSArray *)dln_instanceVariables {
    unsigned int outCount;
    Ivar *ivars = class_copyIvarList([self class], &outCount);
    NSMutableArray *result = [NSMutableArray array];
    for (int i = 0; i < outCount; i++) {
        NSString *type = [NSString decodeType:ivar_getTypeEncoding(ivars[i])];
        NSString *name = [NSString stringWithCString:ivar_getName(ivars[i]) encoding:NSUTF8StringEncoding];
        NSString *ivarDescription = [NSString stringWithFormat:@"%@ %@", type, name];
        [result addObject:ivarDescription];
    }
    free(ivars);
    return result.count ? [result copy] : nil;
}

+ (NSArray *)dln_protocols {
    unsigned int outCount;
    Protocol * const *protocols = class_copyProtocolList([self class], &outCount);
    
    NSMutableArray *result = [NSMutableArray array];
    for (int i = 0; i < outCount; i++) {
        unsigned int adoptedCount;
        Protocol * const *adotedProtocols = protocol_copyProtocolList(protocols[i], &adoptedCount);
        NSString *protocolName = [NSString stringWithCString:protocol_getName(protocols[i]) encoding:NSUTF8StringEncoding];
        
        NSMutableArray *adoptedProtocolNames = [NSMutableArray array];
        for (int idx = 0; idx < adoptedCount; idx++) {
            [adoptedProtocolNames addObject:[NSString stringWithCString:protocol_getName(adotedProtocols[idx]) encoding:NSUTF8StringEncoding]];
        }
        NSString *protocolDescription = protocolName;
        
        if (adoptedProtocolNames.count) {
            protocolDescription = [NSString stringWithFormat:@"%@ <%@>", protocolName, [adoptedProtocolNames componentsJoinedByString:@", "]];
        }
        [result addObject:protocolDescription];
        //free(adotedProtocols);
    }
    //free((__bridge void *)(*protocols));
    return result.count ? [result copy] : nil;
}

+ (NSDictionary *)dln_descriptionForProtocol:(Protocol *)proto {
    NSMutableDictionary *methodsAndProperties = [NSMutableDictionary dictionary];
    
    NSArray *requiredMethods = [[[self class] formattedMethodsForProtocol:proto required:YES instance:NO] arrayByAddingObjectsFromArray:[[self class]formattedMethodsForProtocol:proto required:YES instance:YES]];
    
    NSArray *optionalMethods = [[[self class] formattedMethodsForProtocol:proto required:NO instance:NO] arrayByAddingObjectsFromArray:[[self class]formattedMethodsForProtocol:proto required:NO instance:YES]];
    
    unsigned int propertiesCount;
    NSMutableArray *propertyDescriptions = [NSMutableArray array];
    objc_property_t *properties = protocol_copyPropertyList(proto, &propertiesCount);
    for (int i = 0; i < propertiesCount; i++) {
        [propertyDescriptions addObject:[self formattedPropery:properties[i]]];
    }
    
    if (requiredMethods.count) {
        [methodsAndProperties setObject:requiredMethods forKey:@"@required"];
    }
    if (optionalMethods.count) {
        [methodsAndProperties setObject:optionalMethods forKey:@"@optional"];
    } if (propertyDescriptions.count) {
        [methodsAndProperties setObject:[propertyDescriptions copy] forKey:@"@properties"];
    }
    
    free(properties);
    return methodsAndProperties.count ? [methodsAndProperties copy ] : nil;
}

+ (NSString *)dln_parentClassHierarchy {
    NSMutableString *result = [NSMutableString string];
    getSuper([self class], result);
    return result;
}

#pragma mark - Private

+ (NSArray *)methodsForClass:(Class)class typeFormat:(NSString *)type {
    unsigned int outCount;
    Method *methods = class_copyMethodList(class, &outCount);
    NSMutableArray *result = [NSMutableArray array];
    for (int i = 0; i < outCount; i++) {
        NSString *methodDescription = [NSString stringWithFormat:@"%@ (%@)%@",
                                       type,
                                       [NSString decodeType:method_copyReturnType(methods[i])],
                                       NSStringFromSelector(method_getName(methods[i]))];
        
        NSInteger args = method_getNumberOfArguments(methods[i]);
        NSMutableArray *selParts = [[methodDescription componentsSeparatedByString:@":"] mutableCopy];
        int offset = 2; //1-st arg is object (@), 2-nd is SEL (:)
        
        for (int idx = offset; idx < args; idx++) {
            NSString *returnType = [NSString decodeType:method_copyArgumentType(methods[i], idx)];
            selParts[idx - offset] = [NSString stringWithFormat:@"%@:(%@)arg%d",
                                      selParts[idx - offset],
                                      returnType,
                                      idx - 2];
        }
        [result addObject:[selParts componentsJoinedByString:@" "]];
    }
    free(methods);
    return result.count ? [result copy] : nil;
}

+ (NSArray *)formattedMethodsForProtocol:(Protocol *)proto required:(BOOL)required instance:(BOOL)instance {
    unsigned int methodCount;
    struct objc_method_description *methods = protocol_copyMethodDescriptionList(proto, required, instance, &methodCount);
    NSMutableArray *methodsDescription = [NSMutableArray array];
    for (int i = 0; i < methodCount; i++) {
        [methodsDescription addObject:
         [NSString stringWithFormat:@"%@ (%@)%@",
          instance ? @"-" : @"+",
//#warning return correct type
          @"void",
          NSStringFromSelector(methods[i].name)]];
    }
    
    free(methods);
    return  [methodsDescription copy];
}

+ (NSString *)formattedPropery:(objc_property_t)prop {
    unsigned int attrCount;
    objc_property_attribute_t *attrs = property_copyAttributeList(prop, &attrCount);
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    for (int idx = 0; idx < attrCount; idx++) {
        NSString *name = [NSString stringWithCString:attrs[idx].name encoding:NSUTF8StringEncoding];
        NSString *value = [NSString stringWithCString:attrs[idx].value encoding:NSUTF8StringEncoding];
        [attributes setObject:value forKey:name];
    }
    free(attrs);
    NSMutableString *property = [NSMutableString stringWithFormat:@"@property "];
    NSMutableArray *attrsArray = [NSMutableArray array];
    
    //https://developer.apple.com/library/mac/#documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtPropertyIntrospection.html#//apple_ref/doc/uid/TP40008048-CH101-SW5
    [attrsArray addObject:[attributes objectForKey:@"N"] ? @"nonatomic" : @"atomic"];
    
    if ([attributes objectForKey:@"&"]) {
        [attrsArray addObject:@"strong"];
    } else if ([attributes objectForKey:@"C"]) {
        [attrsArray addObject:@"copy"];
    } else if ([attributes objectForKey:@"W"]) {
        [attrsArray addObject:@"weak"];
    } else {
        [attrsArray addObject:@"assign"];
    }
    if ([attributes objectForKey:@"R"]) {[attrsArray addObject:@"readonly"];}
    if ([attributes objectForKey:@"G"]) {
        [attrsArray addObject:[NSString stringWithFormat:@"getter=%@", [attributes objectForKey:@"G"]]];
    }
    if ([attributes objectForKey:@"S"]) {
        [attrsArray addObject:[NSString stringWithFormat:@"setter=%@", [attributes objectForKey:@"G"]]];
    }
    
    [property appendFormat:@"(%@) %@ %@",
     [attrsArray componentsJoinedByString:@", "],
     [NSString decodeType:[[attributes objectForKey:@"T"] cStringUsingEncoding:NSUTF8StringEncoding]],
     [NSString stringWithCString:property_getName(prop) encoding:NSUTF8StringEncoding]];
    return [property copy];
}
@end
#endif
