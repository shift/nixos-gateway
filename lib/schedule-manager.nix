{ lib, pkgs, ... }:

let
  py = pkgs.python3;
in
{
  check = rule: ''
    import datetime
    import zoneinfo
    import sys

    # Minimal implementation of schedule checking logic
    # This will be expanded into a proper library

    def check_schedule(schedule_config, current_time=None):
        if current_time is None:
            current_time = datetime.datetime.now(datetime.timezone.utc)
            
        tz = zoneinfo.ZoneInfo(schedule_config.get('timezone', 'UTC'))
        local_time = current_time.astimezone(tz)
        
        # Check day of week
        current_day = local_time.strftime('%A')
        allowed_days = schedule_config.get('pattern', {}).get('days', [])
        if current_day not in allowed_days:
            return False
            
        # Check time range
        current_hm = local_time.strftime('%H:%M')
        time_range = schedule_config.get('pattern', {}).get('time', {})
        start_time = time_range.get('start', '00:00')
        end_time = time_range.get('end', '23:59')
        
        if not (start_time <= current_hm <= end_time):
            return False
            
        # Check exceptions (TODO)
        
        return True
  '';
}
