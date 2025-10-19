import logging
import json
import os
import uuid
from pathlib import Path
import asyncio # For broadcast

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, ReplyKeyboardMarkup, KeyboardButton, ReplyKeyboardRemove
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
    ConversationHandler,
    CallbackQueryHandler,
    MessageHandler,
    filters,
)
from telegram.constants import ParseMode
from telegram.error import BadRequest, Forbidden

# --- New Imports for Database and Panel Management ---
import db_utils
from database_models import VpnAccount, VpnPanel # We need these for type hinting and queries
from panel_manager import get_panel_handler, VpnPanelInterface, PANEL_CLASSES

# --- Configuration ---
logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s", level=logging.INFO
)
logger = logging.getLogger(__name__)

# --- Load Environment Variables ---
try:
    BOT_TOKEN = os.getenv("BOT_TOKEN")
    ROOT_ADMIN_CHAT_ID = int(os.getenv("ROOT_ADMIN_CHAT_ID"))
except (TypeError, ValueError):
    logger.critical("FATAL: BOT_TOKEN or ROOT_ADMIN_CHAT_ID not found or invalid in .env file. Exiting.")
    exit(1)


# --- File Paths (Admins and static configs are still files) ---
DATA_DIR = Path(__file__).parent
ADMINS_FILE = DATA_DIR / "admins.json"
PLANS_FILE = DATA_DIR / "plans.json"
SETTINGS_FILE = DATA_DIR / "settings.json"
TICKETS_FILE = DATA_DIR / "tickets.json"

# --- Conversation States (Added new ones) ---
(
    USER_MAIN_MENU,
    CHOOSING_PLAN,
    WAITING_FOR_RECEIPT,
    GETTING_SUPPORT_MESSAGE, ADMIN_REPLYING, USER_REPLYING_TO_TICKET,
    FILES_TUTORIALS_MENU, APPS_OS_MENU,
    MANAGING_ACCOUNTS, # New state for showing user's multiple accounts

    # Admin States
    ADMIN_PANEL,
    MANAGE_SETTINGS_MENU,
    MANAGE_PANELS_MENU, GETTING_PANEL_NAME, GETTING_PANEL_TYPE, GETTING_PANEL_API_URL, GETTING_PANEL_API_TOKEN,
    MANAGE_PAYMENT_MENU,
    GETTING_CARD_NUMBER, GETTING_CARD_HOLDER,
    MANAGE_PLANS_MENU,
    GETTING_PLAN_PRICE, GETTING_PLAN_GB, GETTING_PLAN_DAYS,
    ASKING_USER_LIMIT, GETTING_USER_LIMIT, SELECTING_PANEL_FOR_PLAN,
    MANAGE_ADMINS_MENU, GETTING_REMOVE_ADMIN_ID,
    # Edit & Delete Plan States
    SELECT_PLAN_TO_EDIT, EDITING_PLAN_PRICE, EDITING_PLAN_GB,
    EDITING_PLAN_DAYS, EDITING_GETTING_USER_LIMIT, EDITING_SELECT_PANEL_FOR_PLAN,
    SELECT_PLAN_TO_DELETE,
    # Broadcast States
    GETTING_BROADCAST_MESSAGE, CONFIRM_BROADCAST,
    # Maintenance States
    MANAGE_MAINTENANCE_MENU, GETTING_MAINTENANCE_MESSAGE,
    # Channel Join States
    MANAGE_CHANNEL_MENU, GETTING_CHANNEL_ID,
) = range(45) # Increased range for new states


# ===============================================================
# Helper Functions
# ===============================================================
def load_json(file_path: Path, default_data):
    if not file_path.exists():
        save_json(file_path, default_data)
        return default_data
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, FileNotFoundError):
        logger.warning(f"{file_path.name} corrupt or not found.")
        return default_data

def save_json(file_path: Path, data) -> None:
    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)

# --- Specific Data Functions ---
def load_admins() -> set: return set(load_json(ADMINS_FILE, [ROOT_ADMIN_CHAT_ID]))
def save_admins(admin_ids: set) -> None: global admin_ids_set; admin_ids_set = admin_ids; save_json(ADMINS_FILE, list(admin_ids))
def load_settings() -> dict:
    default_settings = {
        "bot_name": "ParaDoX",
        "maintenance": {"enabled": False, "message": "ربات در حال حاضر در دست تعمیر است. لطفا بعدا تلاش کنید."},
        "force_join": {"enabled": False, "channel_id": None}
    }
    loaded = load_json(SETTINGS_FILE, default_settings)
    for key, value in default_settings.items():
        if key not in loaded:
            loaded[key] = value
    return loaded
def save_settings(s: dict) -> None: global settings; settings = s; save_json(SETTINGS_FILE, s)
def load_plans() -> dict: return load_json(PLANS_FILE, {})
def save_plans(p: dict) -> None: global plans; plans = p; save_json(PLANS_FILE, p)
def load_tickets() -> dict: return load_json(TICKETS_FILE, {})
def save_tickets(t: dict) -> None: save_json(TICKETS_FILE, t)

# Load data at startup
admin_ids_set = load_admins()
settings = load_settings()
plans = load_plans()

def is_admin(user_id: int) -> bool:
    return user_id in admin_ids_set

def is_root_admin(user_id: int) -> bool:
    return user_id == ROOT_ADMIN_CHAT_ID

def format_bytes(byte_count):
    if byte_count is None: return "N/A"
    power = 1024
    n = 0
    power_labels = {0: '', 1: 'K', 2: 'M', 3: 'G', 4: 'T'}
    while byte_count >= power and n < len(power_labels) -1 :
        byte_count /= power
        n += 1
    return f"{byte_count:.2f} {power_labels[n]}B"

def to_shamsi(timestamp):
    if not timestamp or timestamp <= 0:
        return "نامحدود"
    try:
        # Assuming timestamp is a timezone-aware ISO string
        gregorian_date = datetime.fromisoformat(timestamp)
        jalali_date = jdatetime.datetime.fromgregorian(datetime=gregorian_date)
        return jalali_date.strftime("%Y/%m/%d ساعت %H:%M")
    except (TypeError, ValueError):
        return "نامشخص"

def format_price_human_readable(price_in_thousands):
    try:
        price_k = int(price_in_thousands)
        if price_k < 1000:
            return f"{price_k:,} هزار تومان"
        else:
            million_val = price_k / 1000
            formatted_val = f"{million_val:,.1f}"
            if formatted_val.endswith('.0'):
                formatted_val = formatted_val[:-2]
            return f"{formatted_val} میلیون تومان"
    except (ValueError, TypeError):
        return "قیمت نامشخص"

# ===============================================================
# Pre-Handler Checks (Maintenance, Force Join)
# ===============================================================
async def check_maintenance(update: Update, context: ContextTypes.DEFAULT_TYPE) -> bool:
    user_id = update.effective_user.id
    if is_admin(user_id): return False
    
    maintenance_settings = settings.get("maintenance", {})
    if maintenance_settings.get("enabled", False):
        message_text = maintenance_settings.get("message", "ربات در حال حاضر در دست تعمیر است. لطفا بعدا تلاش کنید.")
        if update.callback_query:
            await update.callback_query.answer(message_text, show_alert=True)
        else:
            await update.message.reply_text(message_text)
        return True
    return False

async def check_channel_membership(update: Update, context: ContextTypes.DEFAULT_TYPE) -> bool:
    user = update.effective_user
    if is_admin(user.id): return False

    force_join_settings = settings.get("force_join", {})
    if not force_join_settings.get("enabled", False): return False

    channel_id = force_join_settings.get("channel_id")
    if not channel_id:
        logger.warning("Force join is enabled but no channel ID is set.")
        return False

    try:
        member = await context.bot.get_chat_member(chat_id=channel_id, user_id=user.id)
        if member.status in ['left', 'kicked']:
            raise BadRequest("User is not a member") 
    except BadRequest:
        link = ""
        if str(channel_id).startswith("@"):
            link = f"https://t.me/{channel_id[1:]}"
        
        text = "🙏 برای استفاده از امکانات ربات، لطفا ابتدا در کانال ما عضو شوید و سپس دکمه «عضو شدم» را بزنید."
        keyboard = []
        if link:
            keyboard.append([InlineKeyboardButton("عضویت در کانال", url=link)])
        keyboard.append([InlineKeyboardButton("عضو شدم ✅", callback_data="check_join_again")])
        
        reply_markup = InlineKeyboardMarkup(keyboard)

        if update.callback_query:
            try:
                await update.callback_query.message.edit_text(text, reply_markup=reply_markup)
            except BadRequest: pass
        else:
            await update.message.reply_text(text, reply_markup=reply_markup)
        return True
    except Exception as e:
        logger.error(f"Error checking channel membership for user {user.id} in channel {channel_id}: {e}")
        await context.bot.send_message(chat_id=ROOT_ADMIN_CHAT_ID, text=f"⚠️ خطا در بررسی عضویت کانال: {e}.\n\nممکن است ربات در کانال {channel_id} ادمین نباشد یا شناسه اشتباه باشد.")
        return False

    return False

async def handle_check_join_again(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer("در حال بررسی عضویت شما...")
    return await start(update, context)

# ===============================================================
# Main Entry Point & User Flow
# ===============================================================

async def send_start_menu(user_id: int, context: ContextTypes.DEFAULT_TYPE, custom_text: str = None):
    """Sends the main menu to a specific user."""
    bot_name = settings.get("bot_name", "ParaDoX")
    keyboard = [
        [InlineKeyboardButton("🛒 خرید سرویس", callback_data="buy_service")],
        [InlineKeyboardButton("📊 سرویس‌های من", callback_data="my_accounts")],
        [InlineKeyboardButton("💲 لیست قیمت ها", callback_data="price_list")],
        [InlineKeyboardButton("🗂️ فایل ها و آموزش", callback_data="files_tutorials_menu")],
        [InlineKeyboardButton("📞 پشتیبانی", callback_data="support")],
    ]
    
    if is_admin(user_id):
        keyboard.append([InlineKeyboardButton("🤖 ورود به پنل مدیریت", callback_data="admin_panel_show")])

    text = custom_text or f"سلام! به ربات فروش سرویس {bot_name} خوش آمدید. برای شروع، یک گزینه را انتخاب کنید."
    
    try:
        await context.bot.send_message(
            chat_id=user_id, 
            text=text, 
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
    except Forbidden:
        logger.warning(f"Failed to send message to user {user_id}: Bot was blocked or kicked.")
    except Exception as e:
        logger.error(f"Failed to send start menu to user {user_id}: {e}")
        
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if await check_maintenance(update, context): return ConversationHandler.END
    if await check_channel_membership(update, context): return ConversationHandler.END

    user = update.effective_user
    
    with db_utils.get_db() as db:
        db_utils.get_or_create_user(db,
            telegram_id=user.id, 
            first_name=user.full_name, # Use full_name as first_name
            username=user.username
        )

    bot_name = settings.get("bot_name", "ParaDoX")
    keyboard = [
        [InlineKeyboardButton("🛒 خرید سرویس", callback_data="buy_service")],
        [InlineKeyboardButton("📊 سرویس‌های من", callback_data="my_accounts")],
        [InlineKeyboardButton("💲 لیست قیمت ها", callback_data="price_list")],
        [InlineKeyboardButton("🗂️ فایل ها و آموزش", callback_data="files_tutorials_menu")],
        [InlineKeyboardButton("📞 پشتیبانی", callback_data="support")],
    ]
    
    if is_admin(user.id):
        keyboard.append([InlineKeyboardButton("🤖 ورود به پنل مدیریت", callback_data="admin_panel_show")])

    text = f"سلام! به ربات فروش سرویس {bot_name} خوش آمدید. برای شروع، یک گزینه را انتخاب کنید."
    
    if update.callback_query:
        await update.callback_query.answer()
        try:
            await update.callback_query.message.edit_text(text, reply_markup=InlineKeyboardMarkup(keyboard))
        except BadRequest: pass
    else:
        await update.message.reply_text(text, reply_markup=InlineKeyboardMarkup(keyboard))
        
    return USER_MAIN_MENU

async def my_accounts(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()
    user_id = query.from_user.id
    
    with db_utils.get_db() as db:
        accounts = db_utils.get_user_accounts(db, user_id)
    
    if not accounts:
        await query.message.edit_text("شما هنوز سرویس فعالی خریداری نکرده‌اید.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 بازگشت", callback_data="back_to_start")]]))
        return USER_MAIN_MENU

    text = "📊 **سرویس‌های شما:**\n\nلطفا سرویسی که می‌خواهید مدیریتش کنید را انتخاب نمایید:"
    keyboard = []
    for acc in accounts:
        # Each account gets its own row with a button
        keyboard.append([InlineKeyboardButton(f"سرویس {acc.friendly_name} ({acc.panel.name})", callback_data=f"manage_account_{acc.id}")])
    
    keyboard.append([InlineKeyboardButton("🔙 بازگشت به منوی اصلی", callback_data="back_to_start")])
    
    await query.message.edit_text(text, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode=ParseMode.MARKDOWN)
    return MANAGING_ACCOUNTS

async def manage_single_account(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()
    account_id = int(query.data.split("_")[-1])

    with db_utils.get_db() as db:
        account = db_utils.get_account_by_id(db, account_id)
        if not account or account.user.telegram_id != query.from_user.id:
            await query.message.edit_text("خطا: این سرویس یافت نشد یا متعلق به شما نیست.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 بازگشت", callback_data="my_accounts")]]))
            return MANAGING_ACCOUNTS
        
        try:
            panel_handler = get_panel_handler(account.panel)
            user_info = await panel_handler.get_user(account.panel_username)

            if not user_info:
                raise ValueError("User not found on panel")

            used = user_info.get("used_traffic", 0)
            total = user_info.get("data_limit", 0)
            expire_ts = user_info.get("expire")
            
            # Convert timestamp to timezone-aware datetime string for to_shamsi
            expire_iso = datetime.fromtimestamp(expire_ts, tz=timezone.utc).isoformat() if expire_ts else None
            expire_str = to_shamsi(expire_iso)
            
            remaining_days_str = "نامحدود"
            if expire_ts and expire_ts > 0:
                remaining_seconds = expire_ts - datetime.now().timestamp()
                if remaining_seconds > 0:
                    remaining_days = remaining_seconds / (24 * 60 * 60)
                    remaining_days_str = f"{int(remaining_days)} روز"
                else:
                    remaining_days_str = "منقضی شده"

            status_text = (
                f"📊 **وضعیت سرویس: {account.friendly_name}**\n\n"
                f"👤 نام کاربری: `{user_info.get('username', 'N/A')}`\n"
                f"📈 حجم مصرفی: *{format_bytes(used)}*\n"
                f"📦 حجم کل: *{format_bytes(total) if total > 0 else 'نامحدود'}*\n"
                f"⏳ تاریخ انقضا: *{expire_str}*\n"
                f"🗓️ روزهای باقیمانده: *{remaining_days_str}*"
            )

            keyboard = [
                # TODO: Add Renew/Recharge buttons later
                # [InlineKeyboardButton("🔄 تمدید / شارژ", callback_data=f"renew_{account.id}")],
                [InlineKeyboardButton("🔙 بازگشت به لیست سرویس‌ها", callback_data="my_accounts")]
            ]
            
            # Add subscription link if available
            subscription_url = user_info.get("subscription_url")
            if subscription_url:
                 keyboard.insert(0, [InlineKeyboardButton("🔗 دریافت لینک‌های اتصال", callback_data=f"get_links_{account.id}")])

            await query.message.edit_text(
                status_text, 
                parse_mode=ParseMode.MARKDOWN, 
                reply_markup=InlineKeyboardMarkup(keyboard)
            )

        except Exception as e:
            logger.error(f"Error getting service status for account {account_id}: {e}")
            await query.message.edit_text("خطایی در دریافت اطلاعات سرویس شما از سرور رخ داد. لطفا با پشتیبانی تماس بگیرید.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 بازگشت", callback_data="my_accounts")]]))

    return MANAGING_ACCOUNTS

async def get_account_links(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()
    account_id = int(query.data.split("_")[-1])

    with db_utils.get_db() as db:
        account = db_utils.get_account_by_id(db, account_id)
        if not account or account.user.telegram_id != query.from_user.id:
            await query.message.edit_text("خطا: این سرویس یافت نشد.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 بازگشت", callback_data="my_accounts")]]))
            return MANAGING_ACCOUNTS
            
        try:
            panel_handler = get_panel_handler(account.panel)
            user_info = await panel_handler.get_user(account.panel_username)

            if not user_info: raise ValueError("User info not found")

            subscription_url = user_info.get("subscription_url")
            all_links = user_info.get("links", [])
            
            message_text = "🔗 **لینک‌های اتصال شما:**\n\n"
            if subscription_url:
                message_text += f"لینک کلی (Subscription):\n`{subscription_url}`\n\n"
            
            if all_links:
                message_text += "لینک‌های اتصال جداگانه:\n"
                links_text = "\n\n".join([f"`{link}`" for link in all_links])
                message_text += links_text
            
            if not subscription_url and not all_links:
                message_text = "خطا: لینکی برای این سرویس یافت نشد."

            await query.message.edit_text(
                message_text,
                parse_mode=ParseMode.MARKDOWN,
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 بازگشت", callback_data=f"manage_account_{account.id}")]]))

        except Exception as e:
            logger.error(f"Failed to get links for account {account_id}: {e}")
            await query.message.edit_text("خطا در دریافت لینک‌ها.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 بازگشت", callback_data=f"manage_account_{account.id}")]]))

    return MANAGING_ACCOUNTS

async def show_price_list(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    
    if not plans:
        await query.answer(text="هیچ طرحی تعریف نشده است.", show_alert=True)
        return

    price_list_lines = ["📜 لیست قیمت ها:"]
    for plan_data in plans.values():
        name = plan_data.get('name', 'N/A')
        price = format_price_human_readable(plan_data.get('price', 0))
        price_list_lines.append(f"- {name}: {price}")
        
    price_list_text = "\n".join(price_list_lines)
    if len(price_list_lines) > 10: # Limit lines to avoid huge alert
        price_list_text = "تعداد طرح ها زیاد است. لطفا وارد بخش خرید شوید تا همه را ببینید."
    await query.answer(text=price_list_text, show_alert=True)
    
async def show_plans_to_user(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()
    if not plans:
        await query.message.edit_text("متاسفانه در حال حاضر هیچ طرح فعالی برای فروش وجود ندارد.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 بازگشت", callback_data="back_to_start")]]))
        return USER_MAIN_MENU
    
    plan_details_list = []
    for pid, p_data in plans.items():
        name = p_data.get('name', 'N/A')
        price = format_price_human_readable(p_data.get('price', 0))
        gb = p_data.get('data_limit_gb', 'نامحدود')
        days = p_data.get('duration_days', 'نامحدود')
        users_limit = p_data.get('user_limit')
        user_str = f"{users_limit} کاربره" if users_limit else "نامحدود کاربر"
        plan_details_list.append(f"▫️ *{name}*\n  حجم: {gb} گیگ | زمان: {days} روز | {user_str}\n  قیمت: *{price}*")

    text = "📜 **لیست سرویس‌ها:**\n\n" + "\n\n".join(plan_details_list) + "\n\nلطفا یکی از طرح‌های زیر را برای خرید انتخاب کنید:"

    keyboard = [[InlineKeyboardButton(f"{p['name']}", callback_data=f"plan_{pid}")] for pid, p in plans.items()]
    keyboard.append([InlineKeyboardButton("🔙 بازگشت", callback_data="back_to_start")])
    await query.message.edit_text(text, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode=ParseMode.MARKDOWN)
    return CHOOSING_PLAN

async def handle_plan_selection(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()
    plan_id = query.data.split("_")[1]
    
    if plan_id not in plans:
        await query.message.edit_text("این طرح دیگر موجود نیست.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 بازگشت", callback_data="back_to_start")]]))
        return USER_MAIN_MENU

    context.user_data['selected_plan_id'] = plan_id
    payment_settings = settings.get("payment", {})
    card_enabled = payment_settings.get("card_to_card_enabled", False)
    
    if not card_enabled:
        await query.message.edit_text("❌ در حال حاضر امکان پرداخت وجود ندارد. لطفا بعدا تلاش کنید.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 بازگشت", callback_data="back_to_start")]]))
        return USER_MAIN_MENU

    card_details = payment_settings.get("card_details", {})
    number = card_details.get("number", "N/A")
    holder = card_details.get("holder", "N/A")
    plan = plans[plan_id]
    
    plan_price = format_price_human_readable(plan.get('price', 0))
    text = (f"شما طرح **{plan['name']}** را انتخاب کردید.\nمبلغ قابل پرداخت: **{plan_price}**\n\n"
            f"لطفا مبلغ را به کارت زیر واریز کرده و سپس **اسکرین‌شات رسید** را ارسال نمایید.\n\n"
            f"شماره کارت:\n`{number}`\nبه نام: `{holder}`")
    await query.message.edit_text(text, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 انصراف و بازگشت", callback_data="back_to_start")]]))
    return WAITING_FOR_RECEIPT

async def handle_receipt(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not update.message.photo:
        await update.message.reply_text("لطفا فقط عکس رسید را ارسال کنید.")
        return WAITING_FOR_RECEIPT

    user = update.effective_user
    plan_id = context.user_data.get('selected_plan_id')
    if not plan_id or plan_id not in plans:
        await update.message.reply_text("خطا در یافتن طرح. لطفا از ابتدا شروع کنید: /start")
        return ConversationHandler.END

    tracking_code = str(uuid.uuid4()).split('-')[0].upper()
    plan_data = plans[plan_id]
    
    admin_message_ids = {}
    plan_price = format_price_human_readable(plan_data.get('price', 0))
    caption = (f"✅ **سفارش جدید**\n\n"
               f"**کاربر:** {user.full_name} (`{user.id}`)\n"
               f"**طرح:** {plan_data['name']}\n"
               f"**مبلغ:** {plan_price}\n"
               f"**کد پیگیری:** `{tracking_code}`")
    keyboard = [[InlineKeyboardButton("✅ تایید", callback_data=f"confirm_{tracking_code}"),
                 InlineKeyboardButton("❌ رد", callback_data=f"reject_{tracking_code}")]]
    
    for admin_id in admin_ids_set:
        try:
            msg = await context.bot.send_photo(chat_id=admin_id, photo=update.message.photo[-1].file_id, caption=caption, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode=ParseMode.MARKDOWN)
            admin_message_ids[str(admin_id)] = msg.message_id
        except Exception as e:
            logger.error(f"Failed to send receipt to admin {admin_id}: {e}")

    # --- DATABASE REFACTOR ---
    with db_utils.get_db() as db:
        db_utils.create_order(db,
            tracking_code=tracking_code,
            user_telegram_id=user.id,
            plan_id=plan_id,
            admin_message_ids=admin_message_ids
        )
    # --- END REFACTOR ---

    await update.message.reply_text(f"رسید شما برای بررسی ارسال شد.\nکد پیگیری شما: `{tracking_code}`", parse_mode=ParseMode.MARKDOWN)
    context.user_data.clear()
    return await start(update, context)

# ===============================================================
# Admin Order Decision (Refactored)
# ===============================================================
async def handle_admin_decision(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    await query.answer()
    
    if not is_admin(query.from_user.id):
        await query.answer("⛔️ شما دسترسی لازم برای این کار را ندارید.", show_alert=True)
        return

    action, tracking_code = query.data.split("_")
    admin_name = query.from_user.full_name
    
    with db_utils.get_db() as db:
        order = db_utils.get_order_by_tracking_code(db, tracking_code)
        
        if not order or order.status != 'pending':
            await query.answer("این سفارش قبلا بررسی شده است.", show_alert=True)
            return

        new_status = "confirmed" if action == "confirm" else "rejected"
        plan_data = plans.get(order.plan_id, {"name": "نامشخص", "panel_id": None})
        user_message = ""

        if new_status == "confirmed":
            try:
                panel_id = plan_data.get('panel_id')
                if not panel_id:
                    raise ValueError(f"Plan {order.plan_id} is not linked to any panel!")
                
                panel = db_utils.get_panel_by_id(db, panel_id)
                if not panel:
                    raise ValueError(f"Panel with ID {panel_id} not found in database!")

                panel_handler = get_panel_handler(panel)
                
                # --- Create a unique username ---
                # Example: user_12345_abcd
                panel_username = f"user_{order.user.telegram_id}_{uuid.uuid4().hex[:4]}"
                
                # --- Create user on the panel ---
                created_user_info = await panel_handler.create_user(
                    username=panel_username,
                    plan=plan_data
                )
                if not created_user_info:
                    raise ValueError("Failed to create user on the panel, API returned None.")

                # --- Save the new account to our database ---
                friendly_name = f"{plan_data.get('data_limit_gb', '')}GB"
                db_utils.create_vpn_account(db,
                    user_telegram_id=order.user.telegram_id,
                    panel_id=panel.id,
                    panel_username=created_user_info['username'],
                    friendly_name=friendly_name
                )
                
                # --- Prepare message for the user ---
                subscription_url = created_user_info.get("subscription_url")
                all_links = created_user_info.get("links", [])
                
                user_message = f"✅ سفارش شما برای طرح **{plan_data['name']}** تایید و سرویس شما ساخته شد.\n\n"

                if subscription_url:
                    user_message += f"لینک کلی (Subscription):\n`{subscription_url}`\n\n"
                
                if all_links:
                    user_message += "لینک‌های اتصال جداگانه:\n"
                    links_text = "\n\n".join([f"`{link}`" for link in all_links])
                    user_message += links_text

                if not subscription_url and not all_links:
                    raise ValueError("Neither subscription_url nor links were found in panel response.")
            
            except Exception as e:
                logger.error(f"CRITICAL: Failed to create panel user for order {tracking_code}: {e}")
                user_message = f"✅ سفارش شما تایید شد، اما در ساخت خودکار سرویس مشکلی پیش آمد. لطفا فورا با پشتیبانی تماس بگیرید و کد پیگیری `{tracking_code}` را ارائه دهید."
                await context.bot.send_message(chat_id=query.from_user.id, text=f"🚨 خطا در ساخت سرویس برای سفارش {tracking_code}. لطفا به صورت دستی بسازید. خطا: {e}")
                new_status = "failed" # Set a different status to indicate error
                
        else: # rejected
            user_message = f"❌ سفارش شما برای طرح **{plan_data['name']}** رد شد."
        
        # --- Update order status in DB ---
        db_utils.update_order_status(db, tracking_code, new_status, admin_name)

    try: 
        await context.bot.send_message(chat_id=order.user.telegram_id, text=user_message, parse_mode=ParseMode.MARKDOWN)

        if new_status == "confirmed":
            await send_start_menu(
                user_id=order.user.telegram_id,
                context=context,
                custom_text="سرویس شما فعال شد. می‌توانید از منوی «سرویس‌های من» وضعیت آن را بررسی کنید:"
            )

    except Exception as e: 
        logger.error(f"Failed to notify user {order.user.telegram_id}: {e}")
        
    status_text = "✅ تایید شد" if new_status == "confirmed" else "❌ رد شد"
    if new_status == "failed": status_text = "🚨 خطا در ساخت"
    
    final_caption = query.message.caption + f"\n\n---\n*{status_text} توسط: {admin_name}*"
    
    admin_message_ids = order.admin_message_ids
    if isinstance(admin_message_ids, str): # Handle JSON string from DB
        admin_message_ids = json.loads(admin_message_ids)

    for admin_id, message_id in admin_message_ids.items():
        try: 
            await context.bot.edit_message_caption(chat_id=int(admin_id), message_id=message_id, caption=final_caption, parse_mode=ParseMode.MARKDOWN, reply_markup=None)
        except Exception: pass

# ===============================================================
# Admin Panel & All Sub-menus
# ===============================================================

async def admin_panel_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    # ... (This function remains mostly the same, but we add a new button)
    user = update.effective_user
    query = update.callback_query

    if not is_admin(user.id):
        if query: await query.answer("⛔️ شما دسترسی به این بخش را ندارید.", show_alert=True)
        else: await update.effective_message.reply_text("⛔️ شما دسترسی به این بخش را ندارید.")
        return ConversationHandler.END

    keyboard = [
        [InlineKeyboardButton("📊 آمار ربات", callback_data="admin_stats"), InlineKeyboardButton("📢 ارسال همگانی", callback_data="broadcast_start")],
        [InlineKeyboardButton("⚙️ مدیریت تنظیمات", callback_data="manage_settings"), InlineKeyboardButton("🛒 مدیریت طرح‌ها", callback_data="manage_plans")],
        [InlineKeyboardButton("👤 مدیریت ادمین‌ها", callback_data="manage_admins"), InlineKeyboardButton("🔧 مدیریت حالت تعمیرات", callback_data="manage_maintenance")],
        [InlineKeyboardButton("🖥️ مدیریت پنل‌ها (سرورها)", callback_data="manage_panels")], # NEW BUTTON
        [InlineKeyboardButton("🔙 بازگشت به منوی اصلی", callback_data="back_to_start")]
    ]
    text = f"🤖 *پنل مدیریت ربات {settings.get('bot_name', '')}*\n\nبه پنل مدیریت خوش آمدید. لطفاً یک گزینه را انتخاب کنید:"
    
    if query:
        await query.answer()
        await query.message.edit_text(text, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode=ParseMode.MARKDOWN)
    else:
        await update.message.reply_text(text, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode=ParseMode.MARKDOWN)
    
    return ADMIN_PANEL

# ===============================================================
# ---> Panel Management Flow (NEW)
# ===============================================================
async def manage_panels_menu(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()
    
    with db_utils.get_db() as db:
        panels = db_utils.get_all_panels(db)
        
    keyboard = [
        [InlineKeyboardButton("➕ افزودن پنل جدید", callback_data="add_panel_start")]
    ]
    
    panel_list_items = [f"- {p.name} ({p.panel_type})" for p in panels]
    panel_list = "\n".join(panel_list_items)
    if not panel_list: panel_list = "هیچ پنلی تعریف نشده است."
    
    text = f"🖥️ *مدیریت پنل‌ها (سرورها)*\n\n**پنل‌های فعلی:**\n{panel_list}\n\nلطفا یک گزینه را انتخاب کنید:"

    for panel in panels:
        keyboard.append([
            InlineKeyboardButton(f"❌ حذف {panel.name}", callback_data=f"delete_panel_{panel.id}")
        ])
        
    keyboard.append([InlineKeyboardButton("🔙 بازگشت به پنل اصلی", callback_data="admin_panel_show")])
    
    await query.message.edit_text(text, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode=ParseMode.MARKDOWN)
    return MANAGE_PANELS_MENU

async def delete_panel(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    panel_id = int(query.data.split("_")[-1])

    with db_utils.get_db() as db:
        # First, check if any plan uses this panel
        is_used = any(plan.get('panel_id') == panel_id for plan in plans.values())
        if is_used:
            await query.answer("❌ خطا: این پنل به یک یا چند طرح متصل است. ابتدا طرح‌ها را حذف یا ویرایش کنید.", show_alert=True)
            return MANAGE_PANELS_MENU
            
        db_utils.delete_panel_by_id(db, panel_id)
    
    await query.answer("✅ پنل با موفقیت حذف شد.", show_alert=True)
    return await manage_panels_menu(update, context)


async def add_panel_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()
    context.user_data['new_panel'] = {}
    await query.message.edit_text("لطفا یک **نام دلخواه** برای این پنل وارد کنید (مثلا: سرور آلمان).\n(/cancel برای لغو)")
    return GETTING_PANEL_NAME

async def get_panel_name(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    context.user_data['new_panel']['name'] = update.message.text
    
    keyboard = []
    for panel_type in PANEL_CLASSES.keys():
        keyboard.append([InlineKeyboardButton(panel_type.capitalize(), callback_data=f"paneltype_{panel_type}")])

    await update.message.reply_text("نام دریافت شد. حالا **نوع پنل** را انتخاب کنید:", reply_markup=InlineKeyboardMarkup(keyboard))
    return GETTING_PANEL_TYPE

async def get_panel_type(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()
    panel_type = query.data.split("_")[-1]
    context.user_data['new_panel']['type'] = panel_type
    
    await query.message.edit_text(f"نوع پنل: {panel_type.capitalize()}\n\nحالا لطفا **آدرس کامل API** پنل را وارد کنید.\n(مثال: `https://panel.example.com`)")
    return GETTING_PANEL_API_URL

async def get_panel_api_url(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    context.user_data['new_panel']['api_url'] = update.message.text.rstrip('/')
    await update.message.reply_text("آدرس دریافت شد. در آخر، **توکن یا رمز عبور API** را وارد کنید.")
    return GETTING_PANEL_API_TOKEN

async def get_panel_api_token_and_save(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    context.user_data['new_panel']['api_token'] = update.message.text
    new_panel_data = context.user_data.pop('new_panel')

    with db_utils.get_db() as db:
        db_utils.create_panel(db,
            name=new_panel_data['name'],
            panel_type=new_panel_data['type'],
            api_url=new_panel_data['api_url'],
            api_token=new_panel_data['api_token']
        )
    
    await update.message.reply_text(f"✅ پنل **{new_panel_data['name']}** با موفقیت اضافه شد!")
    
    return await manage_panels_menu(update, context)

# ===============================================================
# ---> Plan Management Flow (Refactored)
# ===============================================================
async def add_plan_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()
    
    # Check if any panel exists before adding a plan
    with db_utils.get_db() as db:
        if not db_utils.get_all_panels(db):
            await query.answer("❌ ابتدا باید حداقل یک پنل (سرور) در بخش «مدیریت پنل‌ها» اضافه کنید.", show_alert=True)
            return MANAGE_PLANS_MENU

    context.user_data['new_plan'] = {}
    await query.message.edit_text("لطفا **قیمت** طرح جدید را به **هزار تومان** وارد کنید (مثال: برای 250,000 تومان، عدد 250 را وارد کنید).\n(/cancel برای لغو)")
    return GETTING_PLAN_PRICE

async def get_plan_days(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    context.user_data['new_plan']['duration_days'] = int(update.message.text)
    keyboard = [
        [InlineKeyboardButton("بله", callback_data="ask_user_limit_yes")],
        [InlineKeyboardButton("خیر", callback_data="ask_user_limit_no")],
    ]
    await update.message.reply_text("آیا تعداد کاربر برای این طرح محدود است؟", reply_markup=InlineKeyboardMarkup(keyboard))
    return ASKING_USER_LIMIT
    
async def handle_user_limit_decision(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()
    
    if query.data == "ask_user_limit_yes":
        await query.message.edit_text("لطفا حداکثر تعداد کاربر را وارد کنید (فقط عدد).")
        return GETTING_USER_LIMIT
    else: # 'no'
        context.user_data['new_plan']['user_limit'] = 0 # 0 means unlimited
        return await ask_for_plan_panel(update, context)
        
async def get_user_limit(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    try:
        limit = int(update.message.text)
        if limit < 1: raise ValueError
        context.user_data['new_plan']['user_limit'] = limit
        return await ask_for_plan_panel(update, context)
    except (ValueError, TypeError):
        await update.message.reply_text("لطفا یک عدد صحیح بزرگتر از صفر وارد کنید.")
        return GETTING_USER_LIMIT

async def ask_for_plan_panel(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    with db_utils.get_db() as db:
        panels = db_utils.get_all_panels(db)
        
    keyboard = []
    for panel in panels:
        keyboard.append([InlineKeyboardButton(f"{panel.name} ({panel.panel_type})", callback_data=f"select_panel_{panel.id}")])

    text = "در نهایت، انتخاب کنید که سرویس‌های این طرح روی کدام پنل (سرور) ساخته شوند:"
    
    if hasattr(update, 'callback_query') and update.callback_query:
        await update.callback_query.message.edit_text(text, reply_markup=InlineKeyboardMarkup(keyboard))
    else:
        await update.message.reply_text(text, reply_markup=InlineKeyboardMarkup(keyboard))

    return SELECTING_PANEL_FOR_PLAN
    
async def save_complete_plan(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()
    
    panel_id = int(query.data.split("_")[-1])
    new_plan = context.user_data.pop('new_plan')
    new_plan['panel_id'] = panel_id

    gb = new_plan.get('data_limit_gb', 'نامحدود')
    days = new_plan.get('duration_days', 'نامحدود')
    users_limit = new_plan.get('user_limit')
    user_str = f"{users_limit} کاربره" if users_limit else "نامحدود کاربر"
    new_plan['name'] = f"سرویس {gb} گیگ - {days} روزه ({user_str})"

    plan_id = str(uuid.uuid4())
    plans[plan_id] = new_plan
    save_plans(plans)
    
    message_text = f"✅ طرح **{new_plan['name']}** با موفقیت اضافه شد!"
    
    await query.message.edit_text(message_text, parse_mode=ParseMode.MARKDOWN)
        
    return await manage_plans_menu(update, context)

# ... (Other admin functions like manage_admins, broadcast, etc. go here)
# ... (They are mostly unchanged from the original code)

# ===============================================================
# A placeholder for the rest of the admin functions to keep the file size reasonable.
# You should copy the following functions from your original file:
# - manage_settings_menu and all its sub-handlers (marzban, wordpress, payment, channel)
# - broadcast_start, get_broadcast_message, confirm_broadcast
# - admin_stats
# - manage_maintenance_menu and its sub-handlers
# - plan editing and deletion flows (edit_plan_start, delete_plan_start, etc.)
# - manage_admins_menu and its sub-handlers
# - request_admin_access and handle_admin_request_decision
# - Support ticket system (support_start, etc.)
# - Files & Tutorials section (files_tutorials_menu, etc.)
#
# IMPORTANT: Remember to update any function that needs to interact with the new
# data structures (e.g., when editing a plan, you might also need to edit its linked panel).
# For now, I'll add a simplified cancel function and the main() function.
# ===============================================================

async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Cancels and restarts the conversation to the main menu."""
    if update.callback_query:
        # Check if the message exists before trying to edit
        if update.callback_query.message:
             await update.callback_query.message.edit_text("عملیات لغو شد.")
    else:
        await update.message.reply_text(
            "عملیات لغو شد.", 
            reply_markup=ReplyKeyboardRemove()
        )
    
    context.user_data.clear()
    
    # Rerun the start function to display the main menu and return its state
    return await start(update, context)


def main() -> None:
    # Initialize the database on startup
    db_utils.init_db()
    
    application = Application.builder().token(BOT_TOKEN).build()
    
    # You will need to rebuild the ConversationHandler with all the new states
    # and entry points. This is a complex task and requires careful mapping.
    # Here is a simplified version to get started.
    
    main_conv_handler = ConversationHandler(
        entry_points=[
            CommandHandler("start", start),
            CallbackQueryHandler(start, pattern="^back_to_start$"),
            CallbackQueryHandler(handle_check_join_again, pattern="^check_join_again$")
        ],
        states={
            USER_MAIN_MENU: [
                CallbackQueryHandler(show_plans_to_user, pattern="^buy_service$"),
                CallbackQueryHandler(admin_panel_command, pattern="^admin_panel_show$"),
                CallbackQueryHandler(my_accounts, pattern="^my_accounts$"),
                # ... other user main menu handlers
            ],
            CHOOSING_PLAN: [
                CallbackQueryHandler(handle_plan_selection, pattern="^plan_"),
                CallbackQueryHandler(start, pattern="^back_to_start$"),
            ],
            WAITING_FOR_RECEIPT: [
                MessageHandler(filters.PHOTO, handle_receipt),
                CallbackQueryHandler(start, pattern="^back_to_start$")
            ],
            MANAGING_ACCOUNTS: [
                CallbackQueryHandler(manage_single_account, pattern=r"^manage_account_"),
                CallbackQueryHandler(get_account_links, pattern=r"^get_links_"),
                CallbackQueryHandler(my_accounts, pattern="^my_accounts$"), # To refresh
                CallbackQueryHandler(start, pattern="^back_to_start$"),
            ],
            ADMIN_PANEL: [
                CallbackQueryHandler(manage_plans_menu, pattern="^manage_plans$"),
                CallbackQueryHandler(manage_panels_menu, pattern="^manage_panels$"),
                CallbackQueryHandler(admin_panel_command, pattern="^admin_panel_show$"), # To refresh
                # ... other admin panel handlers
            ],
            # --- Panel Management States ---
            MANAGE_PANELS_MENU: [
                CallbackQueryHandler(add_panel_start, pattern="^add_panel_start$"),
                CallbackQueryHandler(delete_panel, pattern=r"^delete_panel_"),
                CallbackQueryHandler(admin_panel_command, pattern="^admin_panel_show$"),
            ],
            GETTING_PANEL_NAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, get_panel_name)],
            GETTING_PANEL_TYPE: [CallbackQueryHandler(get_panel_type, pattern=r"^paneltype_")],
            GETTING_PANEL_API_URL: [MessageHandler(filters.TEXT & ~filters.COMMAND, get_panel_api_url)],
            GETTING_PANEL_API_TOKEN: [MessageHandler(filters.TEXT & ~filters.COMMAND, get_panel_api_token_and_save)],

            # --- Plan Management States ---
            MANAGE_PLANS_MENU: [
                CallbackQueryHandler(add_plan_start, pattern="^add_plan_start$"),
                CallbackQueryHandler(admin_panel_command, pattern="^admin_panel_show$"),
                # ... other plan management handlers
            ],
            GETTING_PLAN_PRICE: [MessageHandler(filters.TEXT & ~filters.COMMAND, get_plan_price)], # Assume get_plan_price exists
            # ... and so on for all the other states you defined ...
            GETTING_PLAN_GB: [MessageHandler(filters.TEXT & ~filters.COMMAND, get_plan_gb)], # Assume exists
            GETTING_PLAN_DAYS: [MessageHandler(filters.TEXT & ~filters.COMMAND, get_plan_days)],
            ASKING_USER_LIMIT: [CallbackQueryHandler(handle_user_limit_decision, pattern=r"^ask_user_limit_")],
            GETTING_USER_LIMIT: [MessageHandler(filters.TEXT & ~filters.COMMAND, get_user_limit)],
            SELECTING_PANEL_FOR_PLAN: [CallbackQueryHandler(save_complete_plan, pattern=r"^select_panel_")],
        },
        fallbacks=[CommandHandler("cancel", cancel)],
        per_message=False,
    )
    
    # --- Dummy handlers for functions not fully re-implemented ---
    # You need to replace these with the actual functions from your old code
    async def get_plan_price(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
        context.user_data['new_plan']['price'] = int(update.message.text)
        await update.message.reply_text("قیمت دریافت شد. حالا **حجم** را به گیگابایت وارد کنید (فقط عدد).")
        return GETTING_PLAN_GB

    async def get_plan_gb(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
        context.user_data['new_plan']['data_limit_gb'] = int(update.message.text)
        await update.message.reply_text("حجم دریافت شد. در آخر، **مدت زمان** را به روز وارد کنید (فقط عدد).")
        return GETTING_PLAN_DAYS
        
    async def manage_plans_menu(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
        # A simplified version of manage_plans_menu
        query = update.callback_query
        if query: await query.answer()
        keyboard = [
            [InlineKeyboardButton("➕ افزودن طرح جدید", callback_data="add_plan_start")],
            [InlineKeyboardButton("🔙 بازگشت به پنل اصلی", callback_data="admin_panel_show")]
        ]
        plan_list_items = [f"- {p['name']}" for p in plans.values()]
        plan_list = "\n".join(plan_list_items) or "هیچ طرحی تعریف نشده است."
        text = f"🛒 *مدیریت طرح‌ها*\n\n**طرح‌های فعلی:**\n{plan_list}"
        
        if query:
            await query.message.edit_text(text, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode=ParseMode.MARKDOWN)
        else:
            await update.message.reply_text(text, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode=ParseMode.MARKDOWN)
        return MANAGE_PLANS_MENU

    # --- Add handlers to application ---
    application.add_handler(main_conv_handler)
    
    # Standalone Handlers
    application.add_handler(CallbackQueryHandler(handle_admin_decision, pattern=r"^(confirm|reject)_"))
    application.add_handler(CallbackQueryHandler(show_price_list, pattern="^price_list$"))

    logger.info("Bot is starting...")
    application.run_polling()


if __name__ == "__main__":
    main()

