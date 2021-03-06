//
//  JsonConnection.h
//
//  Thin wrapper around NSURLConnection to make it easier to talk to JSON-producing web services.
//

#import "JsonConnection.h"
#import "JsonResponse.h"
#import "JSON.h"

static NSString *const kREFERER_URL = @"http://your-domain.example.com/";
static NSString *const kREFERER_HEADER = @"Referer";

@implementation JsonConnection

+ (id)connectionWithURL:(NSString *)theURL delegate:(id<JsonConnectionDelegate>)theDelegate userData:(id)theUserData
{
    return [[[JsonConnection alloc] initWithURL:theURL delegate:theDelegate userData:theUserData] autorelease];
}

- (id)initWithURL:(NSString *)theURL delegate:(id<JsonConnectionDelegate>)theDelegate userData:(id)theUserData
{
    self = [super init];
    if (self != nil) 
    {
        data = nil;
        response = nil;
        delegate = theDelegate;
        userData = [theUserData retain];

        NSURL *finalURL = [NSURL URLWithString:theURL]; 
        // NSAssert(finalURL != nil, @"BROKEN URL");
                
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:finalURL cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:60.0];
        [request setValue:kREFERER_URL forHTTPHeaderField:kREFERER_HEADER];
        
        // Be sure to pre-flight all requests
        if ([NSURLConnection canHandleRequest:request])
        {       
            connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
            // NSLog(@"JsonConnection: started loading (%@)", connection);
        }
        else
        {
            [delegate jsonConnection:self didFailWithError:[NSError errorWithDomain:@"JsonConnection" code:JsonConnectionError_Network_Failure userInfo:nil] userData:userData];
        }
    }   
    return self;
}   

- (void)cancel 
{
    [connection cancel];
}

- (void)dealloc 
{
    [connection cancel];
    [userData release];
    [connection release];   
    [data release];
    [response release]; 
    [super dealloc];
}

#pragma mark NSURLConnectionDelegate methods

- (void)connection:(NSURLConnection *)theConnection didReceiveData:(NSData *)incrementalData 
{
    if (data == nil) 
    {
        data = [[NSMutableData alloc] initWithCapacity:2048];
    }
    
    [data appendData:incrementalData];
}

- (void)connection:(NSURLConnection *)theConnection didReceiveResponse:(NSURLResponse *)theResponse
{
    if (response != nil)
    {
        // according to the URL Loading System guide, it is possible to receive 
        // multiple responses in some cases (server redirects; multi-part MIME responses; etc)
        [response release];
    }
    response = [theResponse retain];
}

- (void)connection:(NSURLConnection *)theConnection didFailWithError:(NSError *)theError
{
    [data release];
    data = nil;
    
    [response release];
    response = nil;
    
    [delegate jsonConnection:self didFailWithError:[NSError errorWithDomain:@"JsonConnection" code:JsonConnectionError_Network_Failure userInfo:nil] userData:userData];    
}
 
- (void)connectionDidFinishLoading:(NSURLConnection*)theConnection 
{
    if (data == nil || response == nil)
    {
        [delegate jsonConnection:self didFailWithError:[NSError errorWithDomain:@"JsonConnection" code:JsonConnectionError_Network_Failure userInfo:nil] userData:userData];
        [connection release];
        connection = nil;
        return;
    }
    
    // determine the proper encoding based on the HTTP response, if available
    // (otherwise, assume UTF-8 encoding.)
    NSString *textEncodingName = [response textEncodingName];
    NSStringEncoding likelyEncoding = NSUTF8StringEncoding;
    if (textEncodingName != nil)
    {
        CFStringRef cfsr_textEncodingName = (CFStringRef) textEncodingName;
        CFStringEncoding cf_encoding = CFStringConvertIANACharSetNameToEncoding(cfsr_textEncodingName);
        likelyEncoding = CFStringConvertEncodingToNSStringEncoding(cf_encoding);
    }
    
    // grab the JSON data as a string
    NSString *jsonString = [[NSString alloc] initWithData:data encoding:likelyEncoding];
    
    // turn this on for some really helpful debugging ... NSLog(@"%@", jsonString);
    
    // attempt to create a response (nil indicates failure)
    id jsonResponse = [JsonResponse jsonResponseWithString:jsonString];
    
    // clean up
    [jsonString release];
    [data release];
    data = nil;
    
    [connection release];
    connection = nil;
    
    [response release];
    response = nil;
    
    // send an appropriate message to our delegate
    if (jsonResponse != nil)
    {
        [delegate jsonConnection:self didReceiveResponse:jsonResponse userData:userData];
    }
    else
    {
        [delegate jsonConnection:self didFailWithError:[NSError errorWithDomain:@"JsonConnection" code:JsonConnectionError_Invalid_Json userInfo:nil] userData:userData];
    }
}

@end
