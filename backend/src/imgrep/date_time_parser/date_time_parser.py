import re
import json
import datetime
from dateutil import parser
from dateutil.relativedelta import relativedelta
import spacy
from typing import List, Tuple, Optional, Dict
import calendar

class DateTimeRangeExtractor:
    """
    A comprehensive NLP tool for extracting date and time ranges from natural language text.
     Usage:
        extractor = DateTimeRangeExtractor()
        result = extractor.extract_datetime_ranges("Meeting from Jan 1, 2024 at 9 AM to Jan 5, 2024 at 5 PM")
        json_output = extractor.to_json(result)
        print(json_output)

    """
    
    def __init__(self):
        self.nlp = self._load_spacy_model()
        
        # Current date and time for relative calculations
        self.current_datetime = datetime.datetime.now()
        
        # Compile regex patterns for efficiency
        self._compile_patterns()
        
        # Month mappings
        self.month_names = {
            'january': 1, 'jan': 1, 'february': 2, 'feb': 2, 'march': 3, 'mar': 3,
            'april': 4, 'apr': 4, 'may': 5, 'june': 6, 'jun': 6,
            'july': 7, 'jul': 7, 'august': 8, 'aug': 8, 'september': 9, 'sep': 9,
            'october': 10, 'oct': 10, 'november': 11, 'nov': 11, 'december': 12, 'dec': 12
        }
        
        # Quarter mappings
        self.quarters = {
            'q1': (1, 3), 'q2': (4, 6), 'q3': (7, 9), 'q4': (10, 12),
            'first quarter': (1, 3), 'second quarter': (4, 6),
            'third quarter': (7, 9), 'fourth quarter': (10, 12)
        }
        
        # Time period mappings
        self.time_periods = {
            'morning': (6, 0, 12, 0),    # 6:00 AM to 12:00 PM
            'afternoon': (12, 0, 18, 0), # 12:00 PM to 6:00 PM
            'evening': (18, 0, 22, 0),   # 6:00 PM to 10:00 PM
            'night': (22, 0, 6, 0),      # 10:00 PM to 6:00 AM (next day)
            'midnight': (0, 0, 0, 1),    # 12:00 AM to 12:01 AM
            'noon': (12, 0, 12, 1),      # 12:00 PM to 12:01 PM
        }
    
    def _load_spacy_model(self):
        try:
            print("Loading spaCy model ...")
        except OSError:
            print("Warning: spaCy model 'en_core_web_sm' not found. Attemting to download")
            spacy.cli.download("en_core_web_sm")
            return spacy.load("en_core_web_sm")
    
    def _compile_patterns(self):
        """Compile all regex patterns for date and time range extraction."""
        
        # Explicit date range patterns - improved to handle various formats
        self.explicit_range_patterns = [
            # "from DATE to DATE" or "between DATE and DATE"
            r'(?:from|between)\s+([^,]+?)\s+(?:to|and)\s+([^,\.\!\?;]+)',
            # "DATE - DATE" or "DATE to DATE"
            r'([a-zA-Z]+\s+\d{1,2},?\s+\d{4})\s*[-–—]\s*([a-zA-Z]+\s+\d{1,2},?\s+\d{4})',
            # "DATE through DATE"
            r'([^,]+?)\s+through\s+([^,\.\!\?;]+)',
            # More flexible date range pattern
            r'([a-zA-Z]+\s+\d{1,2},?\s+\d{4})\s+to\s+([a-zA-Z]+\s+\d{1,2},?\s+\d{4})',
        ]
        
        # Time range patterns
        self.time_range_patterns = [
            # "from TIME to TIME" or "between TIME and TIME"
            r'(?:from|between)\s+(\d{1,2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)\s+(?:to|and)\s+(\d{1,2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)',
            # "TIME - TIME"
            r'(\d{1,2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)\s*[-–—]\s*(\d{1,2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)',
            # "at TIME"
            r'(?:at|@)\s+(\d{1,2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)',
        ]
        
        # Combined date-time patterns
        self.datetime_range_patterns = [
            # "from DATE TIME to DATE TIME"
            r'(?:from|between)\s+([^,]+?\s+\d{1,2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)\s+(?:to|and)\s+([^,\.\!\?]+?\s+\d{1,2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)',
            # "on DATE from TIME to TIME"
            r'(?:on)\s+([^,]+?)\s+(?:from|between)\s+(\d{1,2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)\s+(?:to|and)\s+(\d{1,2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)',
        ]
        
        # Period patterns (implicit ranges)
        self.period_patterns = [
            # Year patterns
            r'(?:during|in|for)\s+(\d{4})',
            r'(?:year|yr)\s+(\d{4})',
            # Quarter patterns
            r'(q[1-4])\s+(\d{4})',
            r'(first|second|third|fourth)\s+quarter\s+(?:of\s+)?(\d{4})',
            # Month patterns
            r'(?:during|in)\s+(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s+(\d{4})',
            # Time period patterns
            r'(?:during|in)\s+the\s+(morning|afternoon|evening|night)',
            r'(?:at|around)\s+(midnight|noon)',
        ]
        
        # Relative date and time patterns
        self.relative_patterns = [
            r'(last|this|next)\s+(year|month|quarter|week|day|hour|minute)',
            r'(past|next)\s+(\d+)\s+(years|months|weeks|days|hours|minutes)',
            r'(in|after)\s+(\d+)\s+(years|months|weeks|days|hours|minutes)',
            r'(\d+)\s+(years|months|weeks|days|hours|minutes)\s+ago',
            r'(yesterday|today|tomorrow)',
            r'(?:about|around)\s+(?:an?\s+)?(hour|minute|day|week|month|year)\s+ago',
        ]
    
    def extract_datetime_ranges(self, text: str) -> Dict:
        """
        Extract all date and time ranges from the given text and return as JSON structure.
        
        Args:
            text (str): Input text to analyze
            
        Returns:
            Dict: JSON-serializable dictionary with extraction results
        """
        original_text = text
        text_lower = text.lower().strip()
        results = []
        
        # Extract explicit date ranges
        explicit_ranges = self._extract_explicit_ranges(text_lower)
        results.extend(explicit_ranges)
        
        # Extract time ranges
        time_ranges = self._extract_time_ranges(text, text_lower)
        results.extend(time_ranges)
        
        # Extract combined date-time ranges
        datetime_ranges = self._extract_datetime_ranges(text)
        results.extend(datetime_ranges)
        
        # Extract period-based ranges
        period_ranges = self._extract_period_ranges(text_lower)
        results.extend(period_ranges)
        
        # Extract relative date/time ranges
        relative_ranges = self._extract_relative_ranges(text_lower)
        results.extend(relative_ranges)
        
        # Use spaCy for additional entity recognition 
        if self.nlp:
            spacy_ranges = self._extract_spacy_dates(text_lower)
            results.extend(spacy_ranges)
        
        # Remove duplicates and sort by start datetime
        results = self._deduplicate_and_sort(results)
        
        # Convert datetimes to ISO format for JSON serialization
        for result in results:
            if isinstance(result['start_datetime'], datetime.datetime):
                result['start_datetime'] = result['start_datetime'].isoformat()
            if isinstance(result['end_datetime'], datetime.datetime):
                result['end_datetime'] = result['end_datetime'].isoformat()
            
            # Calculate duration
            start = datetime.datetime.fromisoformat(result['start_datetime'])
            end = datetime.datetime.fromisoformat(result['end_datetime'])
            duration = end - start
            result['duration_seconds'] = int(duration.total_seconds())
        
        # Create JSON response
        json_response = {
            "input_text": original_text,
            "datetime_ranges": results,
        }
        
        return json_response
    
    def _extract_time_ranges(self, original_text: str, text: str) -> List[Dict]:
        """Extract time ranges from text."""
        results = []
        
        for pattern in self.time_range_patterns:
            matches = re.finditer(pattern, original_text, re.IGNORECASE)
            for match in matches:
                if len(match.groups()) == 1:  # Single time (e.g., "at 3 PM")
                    time_text = match.group(1)
                    try:
                        # Parse time and create a 1-minute range
                        parsed_time = parser.parse(time_text)
                        start_datetime = self.current_datetime.replace(
                            hour=parsed_time.hour,
                            minute=parsed_time.minute,
                            second=0,
                            microsecond=0
                        )
                        end_datetime = start_datetime + datetime.timedelta(minutes=1)
                        
                        results.append({
                            'start_datetime': start_datetime,
                            'end_datetime': end_datetime,
                        })
                    except (ValueError, parser.ParserError):
                        continue
                
                elif len(match.groups()) == 2:  # Time range
                    start_time_text, end_time_text = match.groups()
                    try:
                        start_time = parser.parse(start_time_text)
                        end_time = parser.parse(end_time_text)
                        
                        # Use current date for time-only ranges
                        start_datetime = self.current_datetime.replace(
                            hour=start_time.hour,
                            minute=start_time.minute,
                            second=0,
                            microsecond=0
                        )
                        end_datetime = self.current_datetime.replace(
                            hour=end_time.hour,
                            minute=end_time.minute,
                            second=0,
                            microsecond=0
                        )
                        
                        # Handle overnight ranges
                        if end_datetime <= start_datetime:
                            end_datetime += datetime.timedelta(days=1)
                        
                        results.append({
                            'start_datetime': start_datetime,
                            'end_datetime': end_datetime,
                        })
                    except (ValueError, parser.ParserError):
                        continue
        
        # Handle named time periods
        for period_name, (start_hour, start_min, end_hour, end_min) in self.time_periods.items():
            if period_name in text:
                start_datetime = self.current_datetime.replace(
                    hour=start_hour, minute=start_min, second=0, microsecond=0
                )
                
                if period_name == 'night' and end_hour < start_hour:
                    # Handle overnight period
                    end_datetime = (self.current_datetime + datetime.timedelta(days=1)).replace(
                        hour=end_hour, minute=end_min, second=0, microsecond=0
                    )
                else:
                    end_datetime = self.current_datetime.replace(
                        hour=end_hour, minute=end_min, second=0, microsecond=0
                    )
                
                results.append({
                    'start_datetime': start_datetime,
                    'end_datetime': end_datetime,
                })
        
        return results
    
    def _extract_datetime_ranges(self, original_text: str) -> List[Dict]:
        """Extract combined date-time ranges."""
        results = []
        
        for pattern in self.datetime_range_patterns:
            matches = re.finditer(pattern, original_text, re.IGNORECASE)
            for match in matches:
                groups = match.groups()
                
                if len(groups) == 2:  # "from DATETIME to DATETIME"
                    start_text, end_text = groups
                    try:
                        start_datetime = parser.parse(start_text.strip())
                        end_datetime = parser.parse(end_text.strip())
                        
                        if start_datetime <= end_datetime:
                            results.append({
                                'start_datetime': start_datetime,
                                'end_datetime': end_datetime,
                            })
                    except (ValueError, parser.ParserError):
                        continue
                
                elif len(groups) == 3:  # "on DATE from TIME to TIME"
                    date_text, start_time_text, end_time_text = groups
                    try:
                        base_date = parser.parse(date_text.strip()).date()
                        start_time = parser.parse(start_time_text.strip()).time()
                        end_time = parser.parse(end_time_text.strip()).time()
                        
                        start_datetime = datetime.datetime.combine(base_date, start_time)
                        end_datetime = datetime.datetime.combine(base_date, end_time)
                        
                        # Handle overnight time ranges
                        if end_time <= start_time:
                            end_datetime += datetime.timedelta(days=1)
                        
                        results.append({
                            'start_datetime': start_datetime,
                            'end_datetime': end_datetime,
                        })
                    except (ValueError, parser.ParserError):
                        continue
        
        return results
    
    def _extract_explicit_ranges(self, text: str) -> List[Dict]:
        """Extract explicitly stated date ranges."""
        results = []
        
        for pattern in self.explicit_range_patterns:
            matches = re.finditer(pattern, text, re.IGNORECASE)
            for match in matches:
                start_text, end_text = match.groups()
                
                try:
                    start_parsed = parser.parse(start_text.strip())
                    end_parsed = parser.parse(end_text.strip())
                    
                    # Convert to datetime - handle both date and datetime objects
                    if isinstance(start_parsed, datetime.date) and not isinstance(start_parsed, datetime.datetime):
                        start_datetime = datetime.datetime.combine(start_parsed, datetime.time.min)
                    elif isinstance(start_parsed, datetime.datetime):
                        start_datetime = start_parsed
                    else:
                        start_datetime = start_parsed
                    
                    if isinstance(end_parsed, datetime.date) and not isinstance(end_parsed, datetime.datetime):
                        end_datetime = datetime.datetime.combine(end_parsed, datetime.time.max)
                    elif isinstance(end_parsed, datetime.datetime):
                        end_datetime = end_parsed
                    else:
                        end_datetime = end_parsed
                    
                    if start_datetime <= end_datetime:
                        results.append({
                            'start_datetime': start_datetime,
                            'end_datetime': end_datetime,
                        })
                except (ValueError, parser.ParserError) as e:
                    print(f"Failed to parse date range: '{start_text}' to '{end_text}' - {e}")
                    continue
        
        return results
    
    def _extract_period_ranges(self, text: str) -> List[Dict]:
        """Extract date/time ranges from period expressions."""
        results = []
        
        # Year patterns
        year_matches = re.finditer(r'(?:during|in|for|year)\s+(\d{4})', text)
        for match in year_matches:
            year = int(match.group(1))
            results.append({
                'start_datetime': datetime.datetime(year, 1, 1, 0, 0, 0),
                'end_datetime': datetime.datetime(year, 12, 31, 23, 59, 59),
            })
        
        # Quarter patterns
        quarter_matches = re.finditer(r'(q[1-4]|first quarter|second quarter|third quarter|fourth quarter)\s+(?:of\s+)?(\d{4})', text)
        for match in quarter_matches:
            quarter_text = match.group(1).lower()
            year = int(match.group(2))
            
            if quarter_text in self.quarters:
                start_month, end_month = self.quarters[quarter_text]
                start_datetime = datetime.datetime(year, start_month, 1, 0, 0, 0)
                end_datetime = datetime.datetime(year, end_month, 
                                               calendar.monthrange(year, end_month)[1], 23, 59, 59)
                
                results.append({
                    'start_datetime': start_datetime,
                    'end_datetime': end_datetime,
                })
        
        # Month patterns
        month_matches = re.finditer(r'(?:during|in)\s+(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s+(\d{4})', text)
        for match in month_matches:
            month_name = match.group(1).lower()
            year = int(match.group(2))
            
            if month_name in self.month_names:
                month_num = self.month_names[month_name]
                start_datetime = datetime.datetime(year, month_num, 1, 0, 0, 0)
                end_datetime = datetime.datetime(year, month_num, 
                                               calendar.monthrange(year, month_num)[1], 23, 59, 59)
                
                results.append({
                    'start_datetime': start_datetime,
                    'end_datetime': end_datetime,
                })
        
        return results
    
    def _extract_relative_ranges(self, text: str) -> List[Dict]:
        """Extract date/time ranges from relative expressions."""
        results = []
        current_datetime = self.current_datetime
        
        # Last/this/next patterns
        relative_matches = re.finditer(r'(last|this|next)\s+(year|month|quarter|week|day|hour|minute)', text)
        for match in relative_matches:
            direction = match.group(1)
            period = match.group(2)
            
            start_datetime, end_datetime = self._calculate_relative_period(direction, period, current_datetime)
            
            if start_datetime and end_datetime:
                results.append({
                    'start_datetime': start_datetime,
                    'end_datetime': end_datetime,
                })
        
        # Numeric relative patterns
        numeric_matches = re.finditer(r'(past|next|in|after)\s+(\d+)\s+(years|months|weeks|days|hours|minutes)', text)
        for match in numeric_matches:
            direction = match.group(1)
            number = int(match.group(2))
            period = match.group(3)
            
            start_datetime, end_datetime = self._calculate_numeric_relative_period(
                direction, number, period, current_datetime
            )
            
            if start_datetime and end_datetime:
                results.append({
                    'start_datetime': start_datetime,
                    'end_datetime': end_datetime,
                })
        
        # "X ago" patterns
        ago_matches = re.finditer(r'(\d+)\s+(years|months|weeks|days|hours|minutes)\s+ago', text)
        for match in ago_matches:
            number = int(match.group(1))
            period = match.group(2)
            
            if period.startswith('year'):
                past_datetime = current_datetime - relativedelta(years=number)
            elif period.startswith('month'):
                past_datetime = current_datetime - relativedelta(months=number)
            elif period.startswith('week'):
                past_datetime = current_datetime - datetime.timedelta(weeks=number)
            elif period.startswith('day'):
                past_datetime = current_datetime - datetime.timedelta(days=number)
            elif period.startswith('hour'):
                past_datetime = current_datetime - datetime.timedelta(hours=number)
            elif period.startswith('minute'):
                past_datetime = current_datetime - datetime.timedelta(minutes=number)
            else:
                continue
            
            # Create a point in time (1-minute range)
            results.append({
                'start_datetime': past_datetime,
                'end_datetime': past_datetime + datetime.timedelta(minutes=1),
            })
        
        # Yesterday/today/tomorrow
        day_matches = re.finditer(r'(yesterday|today|tomorrow)', text)
        for match in day_matches:
            day_ref = match.group(1)
            
            if day_ref == 'yesterday':
                target_date = (current_datetime - datetime.timedelta(days=1)).date()
            elif day_ref == 'today':
                target_date = current_datetime.date()
            else:  # tomorrow
                target_date = (current_datetime + datetime.timedelta(days=1)).date()
            
            start_datetime = datetime.datetime.combine(target_date, datetime.time.min)
            end_datetime = datetime.datetime.combine(target_date, datetime.time.max)
            
            results.append({
                'start_datetime': start_datetime,
                'end_datetime': end_datetime,
            })
        
        return results
    
    def _calculate_relative_period(self, direction: str, period: str, current_datetime: datetime.datetime) -> Tuple[Optional[datetime.datetime], Optional[datetime.datetime]]:
        """Calculate start and end datetimes for relative periods."""
        try:
            if period == 'year':
                if direction == 'last':
                    start = datetime.datetime(current_datetime.year - 1, 1, 1, 0, 0, 0)
                    end = datetime.datetime(current_datetime.year - 1, 12, 31, 23, 59, 59)
                elif direction == 'this':
                    start = datetime.datetime(current_datetime.year, 1, 1, 0, 0, 0)
                    end = datetime.datetime(current_datetime.year, 12, 31, 23, 59, 59)
                else:  # next
                    start = datetime.datetime(current_datetime.year + 1, 1, 1, 0, 0, 0)
                    end = datetime.datetime(current_datetime.year + 1, 12, 31, 23, 59, 59)
            
            elif period == 'month':
                if direction == 'last':
                    start = (current_datetime.replace(day=1, hour=0, minute=0, second=0, microsecond=0) - relativedelta(months=1))
                    end = (current_datetime.replace(day=1, hour=0, minute=0, second=0, microsecond=0) - datetime.timedelta(microseconds=1))
                elif direction == 'this':
                    start = current_datetime.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
                    next_month = start + relativedelta(months=1)
                    end = next_month - datetime.timedelta(microseconds=1)
                else:  # next
                    start = (current_datetime.replace(day=1, hour=0, minute=0, second=0, microsecond=0) + relativedelta(months=1))
                    end = (start + relativedelta(months=1) - datetime.timedelta(microseconds=1))
            
            elif period == 'week':
                days_since_monday = current_datetime.weekday()
                if direction == 'last':
                    start = (current_datetime - datetime.timedelta(days=days_since_monday + 7)).replace(hour=0, minute=0, second=0, microsecond=0)
                    end = (start + datetime.timedelta(days=6)).replace(hour=23, minute=59, second=59, microsecond=999999)
                elif direction == 'this':
                    start = (current_datetime - datetime.timedelta(days=days_since_monday)).replace(hour=0, minute=0, second=0, microsecond=0)
                    end = (start + datetime.timedelta(days=6)).replace(hour=23, minute=59, second=59, microsecond=999999)
                else:  # next
                    start = (current_datetime - datetime.timedelta(days=days_since_monday) + datetime.timedelta(days=7)).replace(hour=0, minute=0, second=0, microsecond=0)
                    end = (start + datetime.timedelta(days=6)).replace(hour=23, minute=59, second=59, microsecond=999999)
            
            elif period == 'day':
                if direction == 'last':
                    target_date = (current_datetime - datetime.timedelta(days=1)).date()
                elif direction == 'this':
                    target_date = current_datetime.date()
                else:  # next
                    target_date = (current_datetime + datetime.timedelta(days=1)).date()
                
                start = datetime.datetime.combine(target_date, datetime.time.min)
                end = datetime.datetime.combine(target_date, datetime.time.max)
            
            elif period == 'hour':
                if direction == 'last':
                    start = (current_datetime - datetime.timedelta(hours=1)).replace(minute=0, second=0, microsecond=0)
                    end = start.replace(minute=59, second=59, microsecond=999999)
                elif direction == 'this':
                    start = current_datetime.replace(minute=0, second=0, microsecond=0)
                    end = start.replace(minute=59, second=59, microsecond=999999)
                else:  # next
                    start = (current_datetime + datetime.timedelta(hours=1)).replace(minute=0, second=0, microsecond=0)
                    end = start.replace(minute=59, second=59, microsecond=999999)
            
            elif period == 'minute':
                if direction == 'last':
                    start = (current_datetime - datetime.timedelta(minutes=1)).replace(second=0, microsecond=0)
                    end = start.replace(second=59, microsecond=999999)
                elif direction == 'this':
                    start = current_datetime.replace(second=0, microsecond=0)
                    end = start.replace(second=59, microsecond=999999)
                else:  # next
                    start = (current_datetime + datetime.timedelta(minutes=1)).replace(second=0, microsecond=0)
                    end = start.replace(second=59, microsecond=999999)
            
            else:
                return None, None
            
            return start, end
            
        except Exception:
            return None, None
    
    def _calculate_numeric_relative_period(self, direction: str, number: int, period: str, current_datetime: datetime.datetime) -> Tuple[Optional[datetime.datetime], Optional[datetime.datetime]]:
        """Calculate start and end datetimes for numeric relative periods."""
        try:
            if direction in ['past']:
                end_datetime = current_datetime
                if period.startswith('year'):
                    start_datetime = current_datetime - relativedelta(years=number)
                elif period.startswith('month'):
                    start_datetime = current_datetime - relativedelta(months=number)
                elif period.startswith('week'):
                    start_datetime = current_datetime - datetime.timedelta(weeks=number)
                elif period.startswith('day'):
                    start_datetime = current_datetime - datetime.timedelta(days=number)
                elif period.startswith('hour'):
                    start_datetime = current_datetime - datetime.timedelta(hours=number)
                elif period.startswith('minute'):
                    start_datetime = current_datetime - datetime.timedelta(minutes=number)
                else:
                    return None, None
            
            elif direction in ['next']:
                start_datetime = current_datetime
                if period.startswith('year'):
                    end_datetime = current_datetime + relativedelta(years=number)
                elif period.startswith('month'):
                    end_datetime = current_datetime + relativedelta(months=number)
                elif period.startswith('week'):
                    end_datetime = current_datetime + datetime.timedelta(weeks=number)
                elif period.startswith('day'):
                    end_datetime = current_datetime + datetime.timedelta(days=number)
                elif period.startswith('hour'):
                    end_datetime = current_datetime + datetime.timedelta(hours=number)
                elif period.startswith('minute'):
                    end_datetime = current_datetime + datetime.timedelta(minutes=number)
                else:
                    return None, None
            
            elif direction in ['in', 'after']:
                start_datetime = current_datetime
                if period.startswith('year'):
                    target_datetime = current_datetime + relativedelta(years=number)
                elif period.startswith('month'):
                    target_datetime = current_datetime + relativedelta(months=number)
                elif period.startswith('week'):
                    target_datetime = current_datetime + datetime.timedelta(weeks=number)
                elif period.startswith('day'):
                    target_datetime = current_datetime + datetime.timedelta(days=number)
                elif period.startswith('hour'):
                    target_datetime = current_datetime + datetime.timedelta(hours=number)
                elif period.startswith('minute'):
                    target_datetime = current_datetime + datetime.timedelta(minutes=number)
                else:
                    return None, None
                
                # For "in X time" expressions, create a point in time (1-minute range)
                start_datetime = target_datetime
                end_datetime = target_datetime + datetime.timedelta(minutes=1)
            
            else:
                return None, None
            
            return start_datetime, end_datetime
            
        except Exception:
            return None, None
    
    def _extract_spacy_dates(self, text: str) -> List[Dict]:
        """Use spaCy NER to extract additional date entities."""
        if not self.nlp:
            return []
        
        results = []
        doc = self.nlp(text)
        
        date_entities = [ent for ent in doc.ents if ent.label_ in ["DATE", "TIME"]]
        
        for ent in date_entities:
            try:
                # Try to parse the entity as a date/time
                parsed_datetime = parser.parse(ent.text)
                
                # For single dates/times, create a small range
                if ent.label_ == "TIME":
                    # For times, create a 1-minute range
                    start_datetime = self.current_datetime.replace(
                        hour=parsed_datetime.hour,
                        minute=parsed_datetime.minute,
                        second=0,
                        microsecond=0
                    )
                    end_datetime = start_datetime + datetime.timedelta(minutes=1)
                else:
                    # For dates, create a full day range
                    if hasattr(parsed_datetime, 'date'):
                        start_datetime = datetime.datetime.combine(parsed_datetime.date(), datetime.time.min)
                        end_datetime = datetime.datetime.combine(parsed_datetime.date(), datetime.time.max)
                    else:
                        start_datetime = parsed_datetime
                        end_datetime = parsed_datetime + datetime.timedelta(minutes=1)
                
                results.append({
                    'start_datetime': start_datetime,
                    'end_datetime': end_datetime,
                })
            except (ValueError, parser.ParserError):
                continue
        
        return results
    
    def _deduplicate_and_sort(self, results: List[Dict]) -> List[Dict]:
        """Remove duplicates and sort results by start datetime."""
        # Remove duplicates based on datetime ranges
        unique_results = []
        seen_ranges = set()
        
        for result in results:
            range_key = (result['start_datetime'], result['end_datetime'])
            if range_key not in seen_ranges:
                seen_ranges.add(range_key)
                unique_results.append(result)
        
        # Sort by start datetime
        unique_results.sort(key=lambda x: x['start_datetime'])
        
        return unique_results
    
    
    def to_json(self, results: Dict, indent: int = 2) -> str:
        """Convert results to JSON string."""
        return json.dumps(results, indent=indent, default=str)


# Example usage and test cases
def main():
    """Test the DateTimeRangeExtractor with various examples and output JSON."""
    test_texts = [
        "Show me pictures from January 1, 2024 to December 31, 2024.",
        "The project runs from January 1, 2024 to December 31, 2024.",
        "We need the data for Q2 2024.",
        "The conference is scheduled between March 15 and March 18, 2024 from 9 AM to 5 PM.",
        "Meeting tomorrow from 2:30 PM to 4:00 PM.",
        "Sales increased during 2023.",
        "Let's analyze the performance for last year.",
        "The campaign will run from next month through the end of this year.",
        "Revenue dropped in July 2023.",
        "Meeting scheduled for this week at 3 PM.",
        "Data from 2020-2023 shows significant growth.",
        "The fiscal year 2024 budget includes new initiatives.",
        "Give me photos of the dog that I saw in year 2005 and one that I saw in July 2005 and one I saw about an hour ago.",
        "Schedule a call for tomorrow morning between 10:00 AM and 11:30 AM.",
        "The event runs from Monday 9 AM to Friday 6 PM.",
        "I need the reports from last quarter and this month.",
        "Set a reminder for 2 hours from now.",
        "The deadline was 3 days ago at midnight.",
        "Office hours are from 9 AM to 5 PM on weekdays.",
        "The maintenance window is tonight from 11 PM to 2 AM.",
        "I have a vacation planned for next week.",
        "The concert is on December 15th at 8 PM.",
        "Staff meeting every Tuesday at 2 PM.",
        "Project deadline is in 30 days.",
        "The system went down yesterday evening around 6:30 PM.",
        "Training session this afternoon from 1 PM to 4 PM."
    ]
    all_results = []
    
    extractor = DateTimeRangeExtractor()
    for text in test_texts: 
        results = extractor.extract_datetime_ranges(text)
        all_results.append(results)
        
        print(extractor.to_json(results))

    output_filename = "results.json"
    with open(output_filename, 'w', encoding='utf-8') as f:
        json.dump(all_results, f, indent=2, default=str, ensure_ascii=False)
    print(f"Results saved to {output_filename }")
    
    
    

if __name__ == "__main__":
    main()
