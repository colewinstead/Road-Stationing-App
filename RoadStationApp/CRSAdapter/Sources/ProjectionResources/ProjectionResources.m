#import "ProjectionResources.h"
@import Projections;

NSString *RSProjectionDatabasePath(void) {
    @try {
        return [PROJIOUtils databasePath];
    } @catch (NSException *exception) {
        return nil;
    }
}
