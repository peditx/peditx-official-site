import os
import json
from datetime import datetime, timezone

from sqlalchemy import (
    create_engine,
    Column,
    Integer,
    String,
    Boolean,
    ForeignKey,
    DateTime,
    Text,
)
from sqlalchemy.orm import declarative_base, relationship, sessionmaker
from sqlalchemy.sql import func

# --- Database Configuration ---
DB_FILE = "vpn_bot.db"
# Use an absolute path to ensure the db file is always in the bot's root directory
DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), DB_FILE)
DATABASE_URL = f"sqlite:///{DB_PATH}"

# --- SQLAlchemy Setup ---
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


# ===============================================================
#   Database Models (Tables)
# ===============================================================

class User(Base):
    """Represents a Telegram user interacting with the bot."""
    __tablename__ = "users"

    id = Column(Integer, primary_key=True)
    telegram_id = Column(Integer, unique=True, nullable=False, index=True)
    first_name = Column(String, nullable=False)
    username = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # --- Relationships ---
    # A user can have multiple VPN accounts
    accounts = relationship("VpnAccount", back_populates="user", cascade="all, delete-orphan")
    # A user can have multiple orders
    orders = relationship("Order", back_populates="user", cascade="all, delete-orphan")

    def __repr__(self):
        return f"<User(id={self.id}, telegram_id={self.telegram_id}, name='{self.first_name}')>"


class VpnPanel(Base):
    """Stores connection details for different VPN panels (Marzban, Sanaei, etc.)."""
    __tablename__ = "vpn_panels"

    id = Column(Integer, primary_key=True)
    name = Column(String, unique=True, nullable=False) # e.g., "Germany Server"
    panel_type = Column(String, nullable=False) # e.g., "marzban", "sanaei"
    api_url = Column(String, nullable=False)
    api_token = Column(String, nullable=False) # Can be a password or a token
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # --- Relationships ---
    # A panel can have many VPN accounts created on it
    accounts = relationship("VpnAccount", back_populates="panel")

    def __repr__(self):
        return f"<VpnPanel(id={self.id}, name='{self.name}', type='{self.panel_type}')>"


class VpnAccount(Base):
    """Represents a single VPN connection/account owned by a user."""
    __tablename__ = "vpn_accounts"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    panel_id = Column(Integer, ForeignKey("vpn_panels.id"), nullable=False)

    panel_username = Column(String, nullable=False, index=True) # The username on the VPN panel (e.g., 'user_12345_abcd')
    friendly_name = Column(String, nullable=True) # A user-defined name like "My Phone VPN"
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=True)
    
    # --- Relationships ---
    user = relationship("User", back_populates="accounts")
    panel = relationship("VpnPanel", back_populates="accounts")

    def __repr__(self):
        return f"<VpnAccount(id={self.id}, user_id={self.user_id}, panel_username='{self.panel_username}')>"


class Order(Base):
    """Stores information about a user's purchase order."""
    __tablename__ = "orders"

    id = Column(Integer, primary_key=True)
    tracking_code = Column(String, unique=True, nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    plan_id = Column(String, nullable=False) # The ID from the plans.json file
    status = Column(String, default="pending") # pending, confirmed, rejected, failed
    
    # Store message IDs as a JSON string to handle multiple admins
    admin_message_ids = Column(Text, nullable=True, default='{}') 
    
    processed_by = Column(String, nullable=True) # Admin's name who processed the order
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # --- Relationships ---
    user = relationship("User", back_populates="orders")

    def __repr__(self):
        return f"<Order(id={self.id}, tracking_code='{self.tracking_code}', status='{self.status}')>"

