import json
from contextlib import contextmanager
from typing import List, Optional, Dict

from sqlalchemy.orm import Session
from database_models import (
    Base,
    engine,
    SessionLocal,
    User,
    VpnPanel,
    VpnAccount,
    Order,
)

# ===============================================================
#   Database Initialization & Session Management
# ===============================================================

def init_db():
    """Creates all database tables if they don't exist."""
    Base.metadata.create_all(bind=engine)


@contextmanager
def get_db():
    """Provides a transactional scope around a series of operations."""
    db = SessionLocal()
    try:
        yield db
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


# ===============================================================
#   User Functions
# ===============================================================

def get_or_create_user(db: Session, telegram_id: int, first_name: str, username: Optional[str]) -> User:
    """
    Retrieves a user by their Telegram ID. If the user does not exist,
    a new one is created.
    """
    user = db.query(User).filter(User.telegram_id == telegram_id).first()
    if not user:
        user = User(
            telegram_id=telegram_id,
            first_name=first_name,
            username=username
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    return user

def get_all_users(db: Session) -> List[User]:
    """Returns a list of all users in the database."""
    return db.query(User).all()


# ===============================================================
#   VPN Panel Functions
# ===============================================================

def create_panel(db: Session, name: str, panel_type: str, api_url: str, api_token: str) -> VpnPanel:
    """Adds a new VPN panel to the database."""
    new_panel = VpnPanel(
        name=name,
        panel_type=panel_type,
        api_url=api_url,
        api_token=api_token
    )
    db.add(new_panel)
    db.commit()
    db.refresh(new_panel)
    return new_panel

def get_all_panels(db: Session) -> List[VpnPanel]:
    """Returns a list of all configured VPN panels."""
    return db.query(VpnPanel).filter(VpnPanel.is_active == True).all()

def get_panel_by_id(db: Session, panel_id: int) -> Optional[VpnPanel]:
    """Retrieves a single panel by its primary key ID."""
    return db.query(VpnPanel).filter(VpnPanel.id == panel_id).first()
    
def delete_panel_by_id(db: Session, panel_id: int) -> bool:
    """Deletes a panel by its ID."""
    panel = db.query(VpnPanel).filter(VpnPanel.id == panel_id).first()
    if panel:
        db.delete(panel)
        db.commit()
        return True
    return False

# ===============================================================
#   VPN Account Functions
# ===============================================================

def create_vpn_account(db: Session, user_telegram_id: int, panel_id: int, panel_username: str, friendly_name: str) -> VpnAccount:
    """Creates a new VPN account for a user."""
    user = db.query(User).filter(User.telegram_id == user_telegram_id).first()
    if not user:
        raise ValueError(f"User with Telegram ID {user_telegram_id} not found.")

    new_account = VpnAccount(
        user_id=user.id,
        panel_id=panel_id,
        panel_username=panel_username,
        friendly_name=friendly_name
    )
    db.add(new_account)
    db.commit()
    db.refresh(new_account)
    return new_account

def get_user_accounts(db: Session, user_telegram_id: int) -> List[VpnAccount]:
    """Retrieves all VPN accounts for a specific user."""
    return db.query(VpnAccount).join(User).filter(User.telegram_id == user_telegram_id).all()

def get_account_by_id(db: Session, account_id: int) -> Optional[VpnAccount]:
    """Retrieves a single VPN account by its primary key ID."""
    return db.query(VpnAccount).filter(VpnAccount.id == account_id).first()


# ===============================================================
#   Order Functions
# ===============================================================

def create_order(db: Session, tracking_code: str, user_telegram_id: int, plan_id: str, admin_message_ids: Dict[str, int]) -> Order:
    """Creates a new order in the database."""
    user = db.query(User).filter(User.telegram_id == user_telegram_id).first()
    if not user:
        raise ValueError(f"User with Telegram ID {user_telegram_id} not found.")
        
    new_order = Order(
        tracking_code=tracking_code,
        user_id=user.id,
        plan_id=plan_id,
        admin_message_ids=json.dumps(admin_message_ids), # Serialize dict to JSON string
        status="pending"
    )
    db.add(new_order)
    db.commit()
    db.refresh(new_order)
    return new_order

def get_order_by_tracking_code(db: Session, tracking_code: str) -> Optional[Order]:
    """Finds an order by its unique tracking code."""
    return db.query(Order).filter(Order.tracking_code == tracking_code).first()

def update_order_status(db: Session, tracking_code: str, status: str, admin_name: str) -> Optional[Order]:
    """Updates the status and processed_by field of an order."""
    order = db.query(Order).filter(Order.tracking_code == tracking_code).first()
    if order:
        order.status = status
        order.processed_by = admin_name
        db.commit()
        db.refresh(order)
    return order

