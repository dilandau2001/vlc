/*****************************************************************************
 * intf.m: MacOS X interface plugin
 *****************************************************************************
 * Copyright (C) 2002-2003 VideoLAN
 * $Id: intf.m,v 1.84 2003/05/20 15:23:25 hartman Exp $
 *
 * Authors: Jon Lech Johansen <jon-vl@nanocrew.net>
 *          Christophe Massiot <massiot@via.ecp.fr>
 *          Derk-Jan Hartman <thedj@users.sourceforge.net>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111, USA.
 *****************************************************************************/

/*****************************************************************************
 * Preamble
 *****************************************************************************/
#include <stdlib.h>                                      /* malloc(), free() */
#include <sys/param.h>                                    /* for MAXPATHLEN */
#include <string.h>

#include "intf.h"
#include "vout.h"
#include "prefs.h"
#include "playlist.h"
#include "info.h"

/*****************************************************************************
 * Local prototypes.
 *****************************************************************************/
static void Run ( intf_thread_t *p_intf );

/*****************************************************************************
 * OpenIntf: initialize interface
 *****************************************************************************/
int E_(OpenIntf) ( vlc_object_t *p_this )
{   
    intf_thread_t *p_intf = (intf_thread_t*) p_this;

    p_intf->p_sys = malloc( sizeof( intf_sys_t ) );
    if( p_intf->p_sys == NULL )
    {
        return( 1 );
    }

    memset( p_intf->p_sys, 0, sizeof( *p_intf->p_sys ) );
    
    p_intf->p_sys->o_pool = [[NSAutoreleasePool alloc] init];
    
    /* Put Cocoa into multithread mode as soon as possible.
     * http://developer.apple.com/techpubs/macosx/Cocoa/
     * TasksAndConcepts/ProgrammingTopics/Multithreading/index.html
     * This thread does absolutely nothing at all. */
    [NSThread detachNewThreadSelector:@selector(self) toTarget:[NSString string] withObject:nil];
    
    p_intf->p_sys->o_sendport = [[NSPort port] retain];
    p_intf->p_sys->p_sub = msg_Subscribe( p_intf );
    p_intf->pf_run = Run;
    
    [[VLCApplication sharedApplication] autorelease];
    [NSApp initIntlSupport];
    [NSApp setIntf: p_intf];

    [NSBundle loadNibNamed: @"MainMenu" owner: NSApp];

    return( 0 );
}

/*****************************************************************************
 * CloseIntf: destroy interface
 *****************************************************************************/
void E_(CloseIntf) ( vlc_object_t *p_this )
{
    intf_thread_t *p_intf = (intf_thread_t*) p_this;

    msg_Unsubscribe( p_intf, p_intf->p_sys->p_sub );

    [p_intf->p_sys->o_sendport release];
    [p_intf->p_sys->o_pool release];

    free( p_intf->p_sys );
}

/*****************************************************************************
 * Run: main loop
 *****************************************************************************/
static void Run( intf_thread_t *p_intf )
{
    /* Do it again - for some unknown reason, vlc_thread_create() often
     * fails to go to real-time priority with the first launched thread
     * (???) --Meuuh */
    vlc_thread_set_priority( p_intf, VLC_THREAD_PRIORITY_LOW );

    [NSApp run];
}

/*****************************************************************************
 * VLCApplication implementation 
 *****************************************************************************/
@implementation VLCApplication

- (id)init
{
    /* default encoding: ISO-8859-1 */
    i_encoding = NSISOLatin1StringEncoding;

    return( [super init] );
}

- (void)initIntlSupport
{
    char *psz_lang = getenv( "LANG" );

    if( psz_lang == NULL )
    {
        return;
    }

    if( strncmp( psz_lang, "pl", 2 ) == 0 )
    {
        i_encoding = NSISOLatin2StringEncoding;
    }
    else if( strncmp( psz_lang, "ja", 2 ) == 0 ) 
    {
        i_encoding = NSJapaneseEUCStringEncoding;
    }
    else if( strncmp( psz_lang, "ru", 2 ) == 0 )
    {
#define CFSENC2NSSENC(e) CFStringConvertEncodingToNSStringEncoding(e)
        i_encoding = CFSENC2NSSENC( kCFStringEncodingKOI8_R ); 
#undef CFSENC2NSSENC
    }
}

- (NSString *)localizedString:(char *)psz
{
    NSString * o_str = nil;

    if( psz != NULL )
    {
        UInt32 uiLength = (UInt32)strlen( psz );
        NSData * o_data = [NSData dataWithBytes: psz length: uiLength];
        o_str = [[[NSString alloc] initWithData: o_data
                                       encoding: i_encoding] autorelease];
    }

    return( o_str );
}

- (char *)delocalizeString:(NSString *)id
{
    NSData * o_data = [id dataUsingEncoding: i_encoding
                          allowLossyConversion: NO];
    char * psz_string;

    if ( o_data == nil )
    {
        o_data = [id dataUsingEncoding: i_encoding
                     allowLossyConversion: YES];
        psz_string = malloc( [o_data length] + 1 ); 
        [o_data getBytes: psz_string];
        psz_string[ [o_data length] ] = '\0';
        msg_Err( p_intf, "cannot convert to wanted encoding: %s",
                 psz_string );
    }
    else
    {
        psz_string = malloc( [o_data length] + 1 ); 
        [o_data getBytes: psz_string];
        psz_string[ [o_data length] ] = '\0';
    }

    return psz_string;
}

- (NSStringEncoding)getEncoding
{
    return i_encoding;
}

- (void)setIntf:(intf_thread_t *)_p_intf
{
    p_intf = _p_intf;
}

- (intf_thread_t *)getIntf
{
    return( p_intf );
}

- (void)terminate:(id)sender
{
    p_intf->p_vlc->b_die = VLC_TRUE;
}

@end

int ExecuteOnMainThread( id target, SEL sel, void * p_arg )
{
    int i_ret = 0;

    NSAutoreleasePool * o_pool = [[NSAutoreleasePool alloc] init];

    if( [target respondsToSelector: @selector(performSelectorOnMainThread:
                                             withObject:waitUntilDone:)] )
    {
        [target performSelectorOnMainThread: sel
                withObject: [NSValue valueWithPointer: p_arg]
                waitUntilDone: YES];
    }
    else if( NSApp != nil && [NSApp respondsToSelector: @selector(getIntf)] ) 
    {
        NSValue * o_v1;
        NSValue * o_v2;
        NSArray * o_array;
        NSPort * o_recv_port;
        NSInvocation * o_inv;
        NSPortMessage * o_msg;
        intf_thread_t * p_intf;
        NSConditionLock * o_lock;
        NSMethodSignature * o_sig;

        id * val[] = { &o_lock, &o_v2 };

        p_intf = (intf_thread_t *)[NSApp getIntf];

        o_recv_port = [[NSPort port] retain];
        o_v1 = [NSValue valueWithPointer: val]; 
        o_v2 = [NSValue valueWithPointer: p_arg];

        o_sig = [target methodSignatureForSelector: sel];
        o_inv = [NSInvocation invocationWithMethodSignature: o_sig];
        [o_inv setArgument: &o_v1 atIndex: 2];
        [o_inv setTarget: target];
        [o_inv setSelector: sel];

        o_array = [NSArray arrayWithObject:
            [NSData dataWithBytes: &o_inv length: sizeof(o_inv)]];
        o_msg = [[NSPortMessage alloc]
            initWithSendPort: p_intf->p_sys->o_sendport
            receivePort: o_recv_port components: o_array];

        o_lock = [[NSConditionLock alloc] initWithCondition: 0];
        [o_msg sendBeforeDate: [NSDate distantPast]];
        [o_lock lockWhenCondition: 1];
        [o_lock unlock];
        [o_lock release];

        [o_msg release];
        [o_recv_port release];
    } 
    else
    {
        i_ret = 1;
    }

    [o_pool release];

    return( i_ret );
}

/*****************************************************************************
 * playlistChanged: Callback triggered by the intf-change playlist
 * variable, to let the intf update the playlist.
 *****************************************************************************/
int PlaylistChanged( vlc_object_t *p_this, const char *psz_variable,
                     vlc_value_t old_val, vlc_value_t new_val, void *param )
{
    intf_thread_t * p_intf = [NSApp getIntf];
    p_intf->p_sys->b_playlist_update = VLC_TRUE;
    p_intf->p_sys->b_intf_update = VLC_TRUE;
    return VLC_SUCCESS;
}

/*****************************************************************************
 * VLCMain implementation 
 *****************************************************************************/
@implementation VLCMain

- (void)awakeFromNib
{
    [o_window setTitle: _NS("VLC - Controller")];
    [o_window setExcludedFromWindowsMenu: TRUE];

    /* button controls */
    [o_btn_playlist setToolTip: _NS("Playlist")];
    [o_btn_prev setToolTip: _NS("Previous")];
    [o_btn_slower setToolTip: _NS("Slower")];
    [o_btn_play setToolTip: _NS("Play")];
    [o_btn_stop setToolTip: _NS("Stop")];
    [o_btn_faster setToolTip: _NS("Faster")];
    [o_btn_next setToolTip: _NS("Next")];
    [o_btn_prefs setToolTip: _NS("Preferences")];
    [o_volumeslider setToolTip: _NS("Volume")];
    [o_timeslider setToolTip: _NS("Position")];

    /* messages panel */ 
    [o_msgs_panel setDelegate: self];
    [o_msgs_panel setTitle: _NS("Messages")];
    [o_msgs_panel setExcludedFromWindowsMenu: TRUE];
    [o_msgs_btn_crashlog setTitle: _NS("Open CrashLog")];

    /* main menu */
    [o_mi_about setTitle: _NS("About VLC media player")];
    [o_mi_prefs setTitle: _NS("Preferences...")];
    [o_mi_hide setTitle: _NS("Hide VLC")];
    [o_mi_hide_others setTitle: _NS("Hide Others")];
    [o_mi_show_all setTitle: _NS("Show All")];
    [o_mi_quit setTitle: _NS("Quit VLC")];

    [o_mu_file setTitle: _ANS("1:File")];
    [o_mi_open_generic setTitle: _NS("Open...")];
    [o_mi_open_file setTitle: _NS("Open File...")];
    [o_mi_open_disc setTitle: _NS("Open Disc...")];
    [o_mi_open_net setTitle: _NS("Open Network...")];
    [o_mi_open_recent setTitle: _NS("Open Recent")];
    [o_mi_open_recent_cm setTitle: _NS("Clear Menu")];

    [o_mu_edit setTitle: _NS("Edit")];
    [o_mi_cut setTitle: _NS("Cut")];
    [o_mi_copy setTitle: _NS("Copy")];
    [o_mi_paste setTitle: _NS("Paste")];
    [o_mi_clear setTitle: _NS("Clear")];
    [o_mi_select_all setTitle: _NS("Select All")];

    [o_mu_controls setTitle: _NS("Controls")];
    [o_mi_play setTitle: _NS("Play")];
    [o_mi_stop setTitle: _NS("Stop")];
    [o_mi_faster setTitle: _NS("Faster")];
    [o_mi_slower setTitle: _NS("Slower")];
    [o_mi_previous setTitle: _NS("Previous")];
    [o_mi_next setTitle: _NS("Next")];
    [o_mi_loop setTitle: _NS("Loop")];
    [o_mi_fwd setTitle: _NS("Step Forward")];
    [o_mi_bwd setTitle: _NS("Step Backward")];
    [o_mi_program setTitle: _NS("Program")];
    [o_mu_program setTitle: _NS("Program")];
    [o_mi_title setTitle: _NS("Title")];
    [o_mu_title setTitle: _NS("Title")];
    [o_mi_chapter setTitle: _NS("Chapter")];
    [o_mu_chapter setTitle: _NS("Chapter")];
    
    [o_mu_audio setTitle: _NS("Audio")];
    [o_mi_vol_up setTitle: _NS("Volume Up")];
    [o_mi_vol_down setTitle: _NS("Volume Down")];
    [o_mi_mute setTitle: _NS("Mute")];
    [o_mi_audiotrack setTitle: _NS("Audio Track")];
    [o_mu_audiotrack setTitle: _NS("Audio Track")];
    [o_mi_channels setTitle: _NS("Channels")];
    [o_mu_channels setTitle: _NS("Channels")];
    [o_mi_device setTitle: _NS("Device")];
    [o_mu_device setTitle: _NS("Device")];
    
    [o_mu_video setTitle: _NS("Video")];
    [o_mi_half_window setTitle: _NS("Half Size")];
    [o_mi_normal_window setTitle: _NS("Normal Size")];
    [o_mi_double_window setTitle: _NS("Double Size")];
    [o_mi_fittoscreen setTitle: _NS("Fit To Screen")];
    [o_mi_fullscreen setTitle: _NS("Fullscreen")];
    [o_mi_floatontop setTitle: _NS("Float On Top")];
    [o_mi_videotrack setTitle: _NS("Video Track")];
    [o_mu_videotrack setTitle: _NS("Video Track")];
    [o_mi_screen setTitle: _NS("Screen")];
    [o_mu_screen setTitle: _NS("Screen")];
    [o_mi_subtitle setTitle: _NS("Subtitles")];
    [o_mu_subtitle setTitle: _NS("Subtitles")];
    [o_mi_deinterlace setTitle: _NS("Deinterlace")];
    [o_mu_deinterlace setTitle: _NS("Deinterlace")];

    [o_mu_window setTitle: _NS("Window")];
    [o_mi_minimize setTitle: _NS("Minimize Window")];
    [o_mi_close_window setTitle: _NS("Close Window")];
    [o_mi_controller setTitle: _NS("Controller")];
    [o_mi_playlist setTitle: _NS("Playlist")];
    [o_mi_info setTitle: _NS("Info")];
    [o_mi_messages setTitle: _NS("Messages")];

    [o_mi_bring_atf setTitle: _NS("Bring All to Front")];

    [o_mu_help setTitle: _NS("Help")];
    [o_mi_readme setTitle: _NS("ReadMe...")];
    [o_mi_reportabug setTitle: _NS("Report a Bug")];
    [o_mi_website setTitle: _NS("VideoLAN Website")];
    [o_mi_license setTitle: _NS("License")];

    /* dock menu */
    [o_dmi_play setTitle: _NS("Play")];
    [o_dmi_stop setTitle: _NS("Stop")];
    [o_dmi_next setTitle: _NS("Next")];
    [o_dmi_previous setTitle: _NS("Previous")];

    /* error panel */
    [o_error setTitle: _NS("Error")];
    [o_err_lbl setStringValue: _NS("An error has occurred which probably prevented the execution of your request:")];
    [o_err_bug_lbl setStringValue: _NS("If you believe that it is a bug, please follow the instructions at:")]; 
    [o_err_btn_msgs setTitle: _NS("Open Messages Window")];
    [o_err_btn_dismiss setTitle: _NS("Dismiss")];

    [o_info_window setTitle: _NS("Info")];

    [self setSubmenusEnabled: FALSE];
    [self manageVolumeSlider];
}

- (void)applicationWillFinishLaunching:(NSNotification *)o_notification
{
    intf_thread_t * p_intf = [NSApp getIntf];

    o_msg_lock = [[NSLock alloc] init];
    o_msg_arr = [[NSMutableArray arrayWithCapacity: 200] retain];

    o_img_play = [[NSImage imageNamed: @"play"] retain];
    o_img_pause = [[NSImage imageNamed: @"pause"] retain];

    [p_intf->p_sys->o_sendport setDelegate: self];
    [[NSRunLoop currentRunLoop] 
        addPort: p_intf->p_sys->o_sendport
        forMode: NSDefaultRunLoopMode];

    [NSTimer scheduledTimerWithTimeInterval: 0.5
        target: self selector: @selector(manageIntf:)
        userInfo: nil repeats: FALSE];

    [NSThread detachNewThreadSelector: @selector(manage)
        toTarget: self withObject: nil];

    vlc_thread_set_priority( p_intf, VLC_THREAD_PRIORITY_LOW );
}

- (BOOL)application:(NSApplication *)o_app openFile:(NSString *)o_filename
{
    intf_thread_t * p_intf = [NSApp getIntf];
    
    config_PutPsz( p_intf, "sub-file", "" );
    config_PutInt( p_intf, "sub-delay", 0 );
    config_PutFloat( p_intf, "sub-fps", 0.0 );
    config_PutPsz( p_intf, "sout", "" );
    
    [o_playlist appendArray:
        [NSArray arrayWithObject: o_filename] atPos: -1 enqueue: NO];
            
    return( TRUE );
}

- (id)getControls
{
    if ( o_controls )
    {
        return o_controls;
    }
    return nil;
}

- (void)manage
{
    NSDate * o_sleep_date;
    intf_thread_t * p_intf = [NSApp getIntf];
    NSAutoreleasePool * o_pool = [[NSAutoreleasePool alloc] init];

    vlc_thread_set_priority( p_intf, VLC_THREAD_PRIORITY_LOW );

    while( !p_intf->b_die )
    {
        playlist_t * p_playlist;

        vlc_mutex_lock( &p_intf->change_lock );

        p_playlist = vlc_object_find( p_intf, VLC_OBJECT_PLAYLIST, 
                                              FIND_ANYWHERE );

        if( p_playlist != NULL )
        {
            var_AddCallback( p_playlist, "intf-change", PlaylistChanged, self );
            vlc_mutex_lock( &p_playlist->object_lock );
            
            [self manage: p_playlist];
            
            vlc_mutex_unlock( &p_playlist->object_lock );
            vlc_object_release( p_playlist );
        }

        vlc_mutex_unlock( &p_intf->change_lock );

        o_sleep_date = [NSDate dateWithTimeIntervalSinceNow: .5];
        [NSThread sleepUntilDate: o_sleep_date];
    }

    [self terminate];

    [o_pool release];
}

- (void)manage:(playlist_t *)p_playlist
{
    intf_thread_t * p_intf = [NSApp getIntf];

#define p_input p_playlist->p_input

    if( p_input )
    {
        vout_thread_t   * p_vout  = NULL;
        aout_instance_t * p_aout  = NULL; 

        vlc_mutex_lock( &p_input->stream.stream_lock );

        if( !p_input->b_die )
        {
            audio_volume_t i_volume;

            /* New input or stream map change */
            if( p_input->stream.b_changed )
            {
                p_intf->p_sys->b_playing = TRUE;
                [self manageMode: p_playlist];
            }

            vlc_value_t val;

            if( var_Get( (vlc_object_t *)p_input, "intf-change", &val )
                >= 0 && val.b_bool )
            {
                p_intf->p_sys->b_input_update = TRUE;
            }

            p_aout = vlc_object_find( p_intf, VLC_OBJECT_AOUT,
                                              FIND_ANYWHERE );
            if( p_aout != NULL )
            {
                vlc_value_t val;

                if( var_Get( (vlc_object_t *)p_aout, "intf-change", &val )
                    >= 0 && val.b_bool )
                {
                    p_intf->p_sys->b_aout_update = TRUE;
                }

                vlc_object_release( (vlc_object_t *)p_aout );
            }

            aout_VolumeGet( p_intf, &i_volume );
            p_intf->p_sys->b_mute = ( i_volume == 0 );

            p_vout = vlc_object_find( p_intf, VLC_OBJECT_VOUT,
                                              FIND_ANYWHERE );
            if( p_vout != NULL )
            {
                vlc_value_t val;

                if( var_Get( (vlc_object_t *)p_vout, "intf-change", &val )
                    >= 0 && val.b_bool )
                {
                    p_intf->p_sys->b_vout_update = TRUE;
                }

                vlc_object_release( (vlc_object_t *)p_vout );
            }
            [self setupMenus: p_input];
        }
        vlc_mutex_unlock( &p_input->stream.stream_lock );
    }
    else if( p_intf->p_sys->b_playing && !p_intf->b_die )
    {
        p_intf->p_sys->b_playing = FALSE;
        [self manageMode: p_playlist];
    }

#undef p_input
}

- (void)manageMode:(playlist_t *)p_playlist
{
    intf_thread_t * p_intf = [NSApp getIntf];

    if( p_playlist->p_input != NULL )
    {
        p_intf->p_sys->b_current_title_update = 1;
        p_playlist->p_input->stream.b_changed = 0;
        
        msg_Dbg( p_intf, "stream has changed, refreshing interface" );
    }
    else
    {
        vout_thread_t * p_vout = vlc_object_find( p_intf, VLC_OBJECT_VOUT,
                                                          FIND_ANYWHERE );
        if( p_vout != NULL )
        {
            vlc_object_detach( p_vout );
            vlc_object_release( p_vout );

            vlc_mutex_unlock( &p_playlist->object_lock );
            vout_Destroy( p_vout );
            vlc_mutex_lock( &p_playlist->object_lock );
        }
    }

    p_intf->p_sys->b_intf_update = VLC_TRUE;
}

- (void)manageIntf:(NSTimer *)o_timer
{
    intf_thread_t * p_intf = [NSApp getIntf];

    if( p_intf->p_vlc->b_die == VLC_TRUE )
    {
        [o_timer invalidate];
        return;
    }

    playlist_t * p_playlist = vlc_object_find( p_intf, VLC_OBJECT_PLAYLIST,
                                                       FIND_ANYWHERE );

    if( p_playlist == NULL )
    {
        return;
    }

    if ( p_intf->p_sys->b_playlist_update )
    {
        [o_playlist playlistUpdated];
        p_intf->p_sys->b_playlist_update = VLC_FALSE;
    }

    if( p_intf->p_sys->b_current_title_update )
    {
        vout_thread_t   *p_vout = vlc_object_find( p_intf, VLC_OBJECT_VOUT,
                                              FIND_ANYWHERE );
        if( p_vout != NULL )
        {
            id o_vout_wnd;
            NSEnumerator * o_enum = [[NSApp windows] objectEnumerator];
            
            while( ( o_vout_wnd = [o_enum nextObject] ) )
            {
                if( [[o_vout_wnd className] isEqualToString: @"VLCWindow"] )
                {
                    [o_vout_wnd updateTitle];
                }
            }
            vlc_object_release( (vlc_object_t *)p_vout );
        }
        [o_playlist updateRowSelection];
        [o_info updateInfo];

        p_intf->p_sys->b_current_title_update = FALSE;
    }

    vlc_mutex_lock( &p_playlist->object_lock );

#define p_input p_playlist->p_input

    if( p_input != NULL )
    {
        vlc_mutex_lock( &p_input->stream.stream_lock );
    }

    if( p_intf->p_sys->b_intf_update )
    {
        vlc_bool_t b_input = VLC_FALSE;
        vlc_bool_t b_plmul = VLC_FALSE;
        vlc_bool_t b_control = VLC_FALSE;
        vlc_bool_t b_seekable = VLC_FALSE;
        vlc_bool_t b_chapters = VLC_FALSE;

        b_plmul = p_playlist->i_size > 1;

        if( ( b_input = ( p_input != NULL ) ) )
        {
            /* seekable streams */
            b_seekable = p_input->stream.b_seekable;

            /* control buttons for free pace streams */
            b_control = p_input->stream.b_pace_control; 

            /* chapters */
            b_chapters = p_input->stream.p_selected_area->i_part_nb > 1; 

            /* play status */
            p_intf->p_sys->b_play_status = 
                p_input->stream.control.i_status != PAUSE_S;
        }
        else
        {
            /* play status */
            p_intf->p_sys->b_play_status = FALSE;
            [self setSubmenusEnabled: FALSE];
        }

        [self playStatusUpdated: p_intf->p_sys->b_play_status];

        [o_btn_stop setEnabled: b_input];
        [o_btn_faster setEnabled: b_control];
        [o_btn_slower setEnabled: b_control];
        [o_btn_prev setEnabled: (b_plmul || b_chapters)];
        [o_btn_next setEnabled: (b_plmul || b_chapters)];

        [o_timeslider setFloatValue: 0.0];
        [o_timeslider setEnabled: b_seekable];
        [o_timefield setStringValue: @"0:00:00"];

        [self manageVolumeSlider];

        p_intf->p_sys->b_intf_update = VLC_FALSE;
    }

#define p_area p_input->stream.p_selected_area

    if( p_intf->p_sys->b_playing && p_input != NULL )
    {
        vlc_bool_t b_field_update = TRUE;

        if( !p_input->b_die && ( p_intf->p_sys->b_play_status !=
            ( p_input->stream.control.i_status != PAUSE_S ) ) ) 
        {
            p_intf->p_sys->b_play_status =
                !p_intf->p_sys->b_play_status;

            [self playStatusUpdated: p_intf->p_sys->b_play_status]; 
        }

        if( p_input->stream.b_seekable )
        {
            if( f_slider == f_slider_old )
            {
                float f_updated = ( 10000. * p_area->i_tell ) /
                                           p_area->i_size;

                if( f_slider != f_updated )
                {
                    [o_timeslider setFloatValue: f_updated];
                }
            }
            else
            {
                off_t i_seek = ( f_slider * p_area->i_size ) / 10000;

                /* release the lock to be able to seek */
                vlc_mutex_unlock( &p_input->stream.stream_lock );
                input_Seek( p_input, i_seek, INPUT_SEEK_SET );
                vlc_mutex_lock( &p_input->stream.stream_lock );

                /* update the old value */
                f_slider_old = f_slider; 

                b_field_update = VLC_FALSE;
            }
        }

        if( b_field_update )
        {
            NSString * o_time;
            char psz_time[ OFFSETTOTIME_MAX_SIZE ];

            input_OffsetToTime( p_input, psz_time, p_area->i_tell );

            o_time = [NSString stringWithCString: psz_time];
            [o_timefield setStringValue: o_time];
        }

        /* disable screen saver */
        UpdateSystemActivity( UsrActivity );
    }

#undef p_area

    if( p_input != NULL )
    {
        vlc_mutex_unlock( &p_input->stream.stream_lock );
    }

#undef p_input

    vlc_mutex_unlock( &p_playlist->object_lock );
    vlc_object_release( p_playlist );

    [self updateMessageArray];

    [NSTimer scheduledTimerWithTimeInterval: 0.5
        target: self selector: @selector(manageIntf:)
        userInfo: nil repeats: FALSE];
}

- (void)updateMessageArray
{
    int i_start, i_stop;
    intf_thread_t * p_intf = [NSApp getIntf];

    vlc_mutex_lock( p_intf->p_sys->p_sub->p_lock );
    i_stop = *p_intf->p_sys->p_sub->pi_stop;
    vlc_mutex_unlock( p_intf->p_sys->p_sub->p_lock );

    if( p_intf->p_sys->p_sub->i_start != i_stop )
    {
        NSColor *o_white = [NSColor whiteColor];
        NSColor *o_red = [NSColor redColor];
        NSColor *o_yellow = [NSColor yellowColor];
        NSColor *o_gray = [NSColor grayColor];

        NSColor * pp_color[4] = { o_white, o_red, o_yellow, o_gray };
        static const char * ppsz_type[4] = { ": ", " error: ",
                                             " warning: ", " debug: " };

        for( i_start = p_intf->p_sys->p_sub->i_start;
             i_start != i_stop;
             i_start = (i_start+1) % VLC_MSG_QSIZE )
        {
            NSString *o_msg;
            NSDictionary *o_attr;
            NSAttributedString *o_msg_color;

            int i_type = p_intf->p_sys->p_sub->p_msg[i_start].i_type;

            [o_msg_lock lock];

            if( [o_msg_arr count] + 2 > 400 )
            {
                unsigned rid[] = { 0, 1 };
                [o_msg_arr removeObjectsFromIndices: (unsigned *)&rid
                           numIndices: sizeof(rid)/sizeof(rid[0])];
            }

            o_attr = [NSDictionary dictionaryWithObject: o_gray
                forKey: NSForegroundColorAttributeName];
            o_msg = [NSString stringWithFormat: @"%s%s",
                p_intf->p_sys->p_sub->p_msg[i_start].psz_module,
                ppsz_type[i_type]];
            o_msg_color = [[NSAttributedString alloc]
                initWithString: o_msg attributes: o_attr];
            [o_msg_arr addObject: [o_msg_color autorelease]];

            o_attr = [NSDictionary dictionaryWithObject: pp_color[i_type]
                forKey: NSForegroundColorAttributeName];
            o_msg = [NSString stringWithFormat: @"%s\n",
                p_intf->p_sys->p_sub->p_msg[i_start].psz_msg];
            o_msg_color = [[NSAttributedString alloc]
                initWithString: o_msg attributes: o_attr];
            [o_msg_arr addObject: [o_msg_color autorelease]];

            [o_msg_lock unlock];

            if( i_type == 1 )
            {
                NSString *o_my_msg = [NSString stringWithFormat: @"%s: %s\n",
                    p_intf->p_sys->p_sub->p_msg[i_start].psz_module,
                    p_intf->p_sys->p_sub->p_msg[i_start].psz_msg];

                NSRange s_r = NSMakeRange( [[o_err_msg string] length], 0 );
                [o_err_msg setEditable: YES];
                [o_err_msg setSelectedRange: s_r];
                [o_err_msg insertText: o_my_msg];

                [o_error makeKeyAndOrderFront: self];
                [o_err_msg setEditable: NO];
            }
        }

        vlc_mutex_lock( p_intf->p_sys->p_sub->p_lock );
        p_intf->p_sys->p_sub->i_start = i_start;
        vlc_mutex_unlock( p_intf->p_sys->p_sub->p_lock );
    }
}

- (void)playStatusUpdated:(BOOL)b_pause
{
    if( b_pause )
    {
        [o_btn_play setImage: o_img_pause];
        [o_btn_play setToolTip: _NS("Pause")];
        [o_mi_play setTitle: _NS("Pause")];
        [o_dmi_play setTitle: _NS("Pause")];
    }
    else
    {
        [o_btn_play setImage: o_img_play];
        [o_btn_play setToolTip: _NS("Play")];
        [o_mi_play setTitle: _NS("Play")];
        [o_dmi_play setTitle: _NS("Play")];
    }
}

- (void)setSubmenusEnabled:(BOOL)b_enabled
{
    [o_mi_program setEnabled: b_enabled];
    [o_mi_title setEnabled: b_enabled];
    [o_mi_chapter setEnabled: b_enabled];
    [o_mi_audiotrack setEnabled: b_enabled];
    [o_mi_videotrack setEnabled: b_enabled];
    [o_mi_subtitle setEnabled: b_enabled];
    [o_mi_channels setEnabled: b_enabled];
    [o_mi_device setEnabled: b_enabled];
    [o_mi_screen setEnabled: b_enabled];
}

- (void)manageVolumeSlider
{
    audio_volume_t i_volume;
    intf_thread_t * p_intf = [NSApp getIntf];

    aout_VolumeGet( p_intf, &i_volume );

    [o_volumeslider setFloatValue: (float)i_volume / AOUT_VOLUME_STEP]; 
    [o_volumeslider setEnabled: TRUE];

    p_intf->p_sys->b_mute = ( i_volume == 0 );
}

- (void)terminate
{
    NSEvent * o_event;
    vout_thread_t * p_vout;
    playlist_t * p_playlist;
    intf_thread_t * p_intf = [NSApp getIntf];

    /*
     * Free playlists
     */
    msg_Dbg( p_intf, "removing all playlists" );
    while( (p_playlist = vlc_object_find( p_intf->p_vlc, VLC_OBJECT_PLAYLIST,
                                          FIND_CHILD )) )
    {
        vlc_object_detach( p_playlist );
        vlc_object_release( p_playlist );
        playlist_Destroy( p_playlist );
    }

    /*
     * Free video outputs
     */
    msg_Dbg( p_intf, "removing all video outputs" );
    while( (p_vout = vlc_object_find( p_intf->p_vlc, 
                                      VLC_OBJECT_VOUT, FIND_CHILD )) )
    {
        vlc_object_detach( p_vout );
        vlc_object_release( p_vout );
        vout_Destroy( p_vout );
    }

    if( o_img_pause != nil )
    {
        [o_img_pause release];
        o_img_pause = nil;
    }

    if( o_img_play != nil )
    {
        [o_img_play release];
        o_img_play = nil;
    }

    if( o_msg_arr != nil )
    {
        [o_msg_arr removeAllObjects];
        [o_msg_arr release];
        o_msg_arr = nil;
    }

    if( o_msg_lock != nil )
    {
        [o_msg_lock release];
        o_msg_lock = nil;
    }

    [NSApp stop: nil];

    /* write cached user defaults to disk */
    [[NSUserDefaults standardUserDefaults] synchronize];

    /* send a dummy event to break out of the event loop */
    o_event = [NSEvent mouseEventWithType: NSLeftMouseDown
                location: NSMakePoint( 1, 1 ) modifierFlags: 0
                timestamp: 1 windowNumber: [[NSApp mainWindow] windowNumber]
                context: [NSGraphicsContext currentContext] eventNumber: 1
                clickCount: 1 pressure: 0.0];
    [NSApp postEvent: o_event atStart: YES];
}

- (void)setupMenus:(input_thread_t *)p_input
{
    intf_thread_t * p_intf = [NSApp getIntf];
    vlc_value_t val;

    if( p_intf->p_sys->b_input_update )
    {
        val.b_bool = FALSE;

        [self setupVarMenu: o_mi_program target: (vlc_object_t *)p_input
            var: "program" selector: @selector(toggleVar:)];

        [self setupVarMenu: o_mi_title target: (vlc_object_t *)p_input
            var: "title" selector: @selector(toggleVar:)];

        [self setupVarMenu: o_mi_chapter target: (vlc_object_t *)p_input
            var: "chapter" selector: @selector(toggleVar:)];

        [self setupVarMenu: o_mi_audiotrack target: (vlc_object_t *)p_input
            var: "audio-es" selector: @selector(toggleVar:)];

        [self setupVarMenu: o_mi_videotrack target: (vlc_object_t *)p_input
            var: "video-es" selector: @selector(toggleVar:)];

        [self setupVarMenu: o_mi_subtitle target: (vlc_object_t *)p_input
            var: "spu-es" selector: @selector(toggleVar:)];

        p_intf->p_sys->b_input_update = FALSE;
        var_Set( (vlc_object_t *)p_input, "intf-change", val );
    }

    if ( p_intf->p_sys->b_aout_update )
    {
        aout_instance_t * p_aout = vlc_object_find( p_intf, VLC_OBJECT_AOUT,
                                                    FIND_ANYWHERE );

        if ( p_aout != NULL )
        {
            val.b_bool = FALSE;
            
            [self setupVarMenu: o_mi_channels target: (vlc_object_t *)p_aout
                var: "audio-channels" selector: @selector(toggleVar:)];

            [self setupVarMenu: o_mi_device target: (vlc_object_t *)p_aout
                var: "audio-device" selector: @selector(toggleVar:)];
            var_Set( (vlc_object_t *)p_aout, "intf-change", val );
            
            vlc_object_release( (vlc_object_t *)p_aout );
        }
        p_intf->p_sys->b_aout_update = FALSE;
    }

    if( p_intf->p_sys->b_vout_update )
    {
        vout_thread_t * p_vout = vlc_object_find( p_intf, VLC_OBJECT_VOUT,
                                                          FIND_ANYWHERE );

        if ( p_vout != NULL )
        {
            val.b_bool = FALSE;

            [self setupVarMenu: o_mi_screen target: (vlc_object_t *)p_vout
                var: "video-device" selector: @selector(toggleVar:)];
            var_Set( (vlc_object_t *)p_vout, "intf-change", val );
            
            vlc_object_release( (vlc_object_t *)p_vout );
            [o_mi_close_window setEnabled: TRUE];
        }
        
        p_intf->p_sys->b_vout_update = FALSE;
    }
}

- (void)setupVarMenu:(NSMenuItem *)o_mi
                     target:(vlc_object_t *)p_object
                     var:(const char *)psz_variable
                     selector:(SEL)pf_callback
{
    int i, i_nb_items, i_value;
    NSMenu * o_menu = [o_mi submenu];
    vlc_value_t val, text;
    
    [o_mi setTag: (int)psz_variable];
    
    /* remove previous items */
    i_nb_items = [o_menu numberOfItems];
    for( i = 0; i < i_nb_items; i++ )
    {
        [o_menu removeItemAtIndex: 0];
    }

    if ( var_Get( p_object, psz_variable, &val ) < 0 )
    {
        return;
    }
    i_value = val.i_int;

    if ( var_Change( p_object, psz_variable,
                     VLC_VAR_GETLIST, &val, &text ) < 0 )
    {
        return;
    }

    /* make (un)sensitive */
    [o_mi setEnabled: ( val.p_list->i_count > 1 )];

    for ( i = 0; i < val.p_list->i_count; i++ )
    {
        NSMenuItem * o_lmi;
        NSString * o_title;

        if ( text.p_list->p_values[i].psz_string )
        {
            o_title = [NSApp localizedString: text.p_list->p_values[i].psz_string];
        }
        else
        {
            o_title = [NSString stringWithFormat: @"%s - %d",
                        strdup(psz_variable), val.p_list->p_values[i].i_int ];
        }
        o_lmi = [o_menu addItemWithTitle: [o_title copy]
                action: pf_callback keyEquivalent: @""];
        
        /* FIXME: this isn't 64-bit clean ! */
        [o_lmi setTag: val.p_list->p_values[i].i_int];
        [o_lmi setRepresentedObject:
            [NSValue valueWithPointer: p_object]];
        [o_lmi setTarget: o_controls];

        if ( i_value == val.p_list->p_values[i].i_int )
            [o_lmi setState: NSOnState];
    }

    var_Change( p_object, psz_variable, VLC_VAR_FREELIST,
                &val, &text );

}

- (IBAction)clearRecentItems:(id)sender
{
    [[NSDocumentController sharedDocumentController]
                          clearRecentDocuments: nil];
}

- (void)openRecentItem:(id)sender
{
    [self application: nil openFile: [sender title]]; 
}

- (IBAction)viewPreferences:(id)sender
{
    [o_prefs showPrefs];
}

- (IBAction)timesliderUpdate:(id)sender
{
    float f_updated;

    switch( [[NSApp currentEvent] type] )
    {
        case NSLeftMouseUp:
        case NSLeftMouseDown:
            f_slider = [sender floatValue];
            return;

        case NSLeftMouseDragged:
            f_updated = [sender floatValue];
            break;

        default:
            return;
    }

    intf_thread_t * p_intf = [NSApp getIntf];

    playlist_t * p_playlist = vlc_object_find( p_intf, VLC_OBJECT_PLAYLIST,
                                                       FIND_ANYWHERE );

    if( p_playlist == NULL )
    {
        return;
    }

    vlc_mutex_lock( &p_playlist->object_lock );

    if( p_playlist->p_input != NULL )
    {
        off_t i_tell;
        NSString * o_time;
        char psz_time[ OFFSETTOTIME_MAX_SIZE ];

#define p_area p_playlist->p_input->stream.p_selected_area
        vlc_mutex_lock( &p_playlist->p_input->stream.stream_lock );
        i_tell = f_updated / 10000. * p_area->i_size;
        input_OffsetToTime( p_playlist->p_input, psz_time, i_tell );
        vlc_mutex_unlock( &p_playlist->p_input->stream.stream_lock );
#undef p_area

        o_time = [NSString stringWithCString: psz_time];
        [o_timefield setStringValue: o_time]; 
    }

    vlc_mutex_unlock( &p_playlist->object_lock );
    vlc_object_release( p_playlist );
}

- (IBAction)closeError:(id)sender
{
    [o_err_msg setString: @""];
    [o_error performClose: self];
}

- (IBAction)openReadMe:(id)sender
{
    NSString * o_path = [[NSBundle mainBundle] 
        pathForResource: @"README.MacOSX" ofType: @"rtf"]; 

    [[NSWorkspace sharedWorkspace] openFile: o_path 
                                   withApplication: @"TextEdit"];
}

- (IBAction)reportABug:(id)sender
{
    NSURL * o_url = [NSURL URLWithString: 
        @"http://www.videolan.org/support/bug-reporting.html"];

    [[NSWorkspace sharedWorkspace] openURL: o_url];
}

- (IBAction)openWebsite:(id)sender
{
    NSURL * o_url = [NSURL URLWithString: @"http://www.videolan.org"];

    [[NSWorkspace sharedWorkspace] openURL: o_url];
}

- (IBAction)openLicense:(id)sender
{
    NSString * o_path = [[NSBundle mainBundle] 
        pathForResource: @"COPYING" ofType: nil];

    [[NSWorkspace sharedWorkspace] openFile: o_path 
                                   withApplication: @"TextEdit"];
}

- (IBAction)openCrashLog:(id)sender
{
    NSString * o_path = [@"~/Library/Logs/CrashReporter/VLC.crash.log"
                                    stringByExpandingTildeInPath]; 

    
    if ( [[NSFileManager defaultManager] fileExistsAtPath: o_path ] )
    {
        [[NSWorkspace sharedWorkspace] openFile: o_path 
                                    withApplication: @"Console"];
    }
    else
    {
        NSBeginInformationalAlertSheet(_NS("No CrashLog found"), @"Continue", nil, nil, o_msgs_panel, self, NULL, NULL, nil, _NS("Either you are running Mac OS X pre 10.2 or you haven't experienced any heavy crashes yet.") );

    }
}

- (void)windowDidBecomeKey:(NSNotification *)o_notification
{
    if( [o_notification object] == o_msgs_panel )
    {
        id o_msg;
        NSEnumerator * o_enum;

        [o_messages setString: @""]; 

        [o_msg_lock lock];

        o_enum = [o_msg_arr objectEnumerator];

        while( ( o_msg = [o_enum nextObject] ) != nil )
        {
            [o_messages insertText: o_msg];
        }

        [o_msg_lock unlock];
    }
}

@end

@implementation VLCMain (NSMenuValidation)

- (BOOL)validateMenuItem:(NSMenuItem *)o_mi
{
    BOOL bEnabled = TRUE;

    /* Recent Items Menu */

    if( [[o_mi title] isEqualToString: _NS("Clear Menu")] )
    {
        NSMenu * o_menu = [o_mi_open_recent submenu];
        int i_nb_items = [o_menu numberOfItems];
        NSArray * o_docs = [[NSDocumentController sharedDocumentController]
                                                       recentDocumentURLs];
        UInt32 i_nb_docs = [o_docs count];

        if( i_nb_items > 1 )
        {
            while( --i_nb_items )
            {
                [o_menu removeItemAtIndex: 0];
            }
        }

        if( i_nb_docs > 0 )
        {
            NSURL * o_url;
            NSString * o_doc;

            [o_menu insertItem: [NSMenuItem separatorItem] atIndex: 0];

            while( TRUE )
            {
                i_nb_docs--;

                o_url = [o_docs objectAtIndex: i_nb_docs];

                if( [o_url isFileURL] )
                {
                    o_doc = [o_url path];
                }
                else
                {
                    o_doc = [o_url absoluteString];
                }

                [o_menu insertItemWithTitle: o_doc
                    action: @selector(openRecentItem:)
                    keyEquivalent: @"" atIndex: 0]; 

                if( i_nb_docs == 0 )
                {
                    break;
                }
            } 
        }
        else
        {
            bEnabled = FALSE;
        }
    }

    return( bEnabled );
}

@end

@implementation VLCMain (Internal)

- (void)handlePortMessage:(NSPortMessage *)o_msg
{
    id ** val;
    NSData * o_data;
    NSValue * o_value;
    NSInvocation * o_inv;
    NSConditionLock * o_lock;
 
    o_data = [[o_msg components] lastObject];
    o_inv = *((NSInvocation **)[o_data bytes]); 
    [o_inv getArgument: &o_value atIndex: 2];
    val = (id **)[o_value pointerValue];
    [o_inv setArgument: val[1] atIndex: 2];
    o_lock = *(val[0]);

    [o_lock lock];
    [o_inv invoke];
    [o_lock unlockWithCondition: 1];
}

@end
