import requests
import json
from datetime import datetime
from abc import ABC, abstractmethod
from typing import Dict, Optional, Any

# Assuming database_models.py exists and has VpnPanel defined
# This is just for type hinting, no circular dependency is created.
from database_models import VpnPanel


class VpnPanelInterface(ABC):
    """
    An abstract base class (interface) that defines the required methods
    for any VPN panel integration. This ensures that all panel handlers
    have a consistent structure.
    """
    def __init__(self, panel_details: VpnPanel):
        self.panel = panel_details

    @abstractmethod
    async def create_user(self, username: str, plan: Dict) -> Optional[Dict[str, Any]]:
        """
        Creates a new user on the VPN panel.

        :param username: The desired username for the new user.
        :param plan: A dictionary containing plan details like data_limit_gb, duration_days, etc.
        :return: A dictionary with the created user's info (username, subscription_url, links) or None on failure.
        """
        pass

    @abstractmethod
    async def get_user(self, username: str) -> Optional[Dict[str, Any]]:
        """
        Retrieves details for a specific user from the panel.

        :param username: The username to look up.
        :return: A dictionary with user details (used_traffic, data_limit, expire, etc.) or None if not found.
        """
        pass

    @abstractmethod
    async def delete_user(self, username: str) -> bool:
        """
        Deletes a user from the panel.

        :param username: The username to delete.
        :return: True if deletion was successful, False otherwise.
        """
        pass

    @abstractmethod
    async def modify_user(self, username: str, modifications: Dict) -> bool:
        """
        Modifies an existing user (e.g., extends expiry, adds data).

        :param username: The username to modify.
        :param modifications: A dictionary of changes to apply.
        :return: True if modification was successful, False otherwise.
        """
        pass


class MarzbanPanel(VpnPanelInterface):
    """Handles all API interactions with a Marzban panel."""

    def _get_auth_token(self) -> str:
        """Logs in to the panel and returns an access token."""
        login_url = f"{self.panel.api_url}/api/admin/token"
        # In Marzban, the "token" is the password for the admin user.
        login_data = {"username": "admin", "password": self.panel.api_token}
        try:
            # Using verify=False for self-signed certificates, consider adding a cert path in production.
            response = requests.post(login_url, data=login_data, verify=False, timeout=10)
            response.raise_for_status()
            return response.json()["access_token"]
        except requests.exceptions.RequestException as e:
            print(f"Marzban login failed: {e}")
            raise ConnectionError("Could not connect to Marzban panel to get token.")

    async def create_user(self, username: str, plan: Dict) -> Optional[Dict[str, Any]]:
        try:
            access_token = self._get_auth_token()
            headers = {"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"}
            create_user_url = f"{self.panel.api_url}/api/user"

            duration_days = plan.get('duration_days', 0)
            expire_timestamp = 0
            if duration_days > 0:
                duration_seconds = duration_days * 24 * 60 * 60
                expire_timestamp = int(datetime.now().timestamp()) + duration_seconds

            data_limit_bytes = plan.get('data_limit_gb', 0) * 1024 * 1024 * 1024

            user_payload = {
                "username": username,
                "expire": expire_timestamp,
                "data_limit": data_limit_bytes,
                "status": "active",
                "data_limit_reset_strategy": "no_reset",
                "proxies": {"vless": {}, "vmess": {}},
                "inbounds": {}
            }
            if plan.get('user_limit', 0) > 0:
                user_payload['on_hold_user_limit'] = plan['user_limit']

            response = requests.post(create_user_url, headers=headers, json=user_payload, verify=False, timeout=15)
            response.raise_for_status()
            user_info = response.json()
            
            # Ensure the subscription URL is absolute
            sub_url = user_info.get("subscription_url")
            if sub_url and not sub_url.startswith('http'):
                sub_url = f"{self.panel.api_url}{sub_url}"

            return {
                "username": user_info.get("username"),
                "subscription_url": sub_url,
                "links": user_info.get("links", [])
            }
        except (requests.exceptions.RequestException, ConnectionError) as e:
            print(f"Error creating Marzban user {username}: {e}")
            return None

    async def get_user(self, username: str) -> Optional[Dict[str, Any]]:
        try:
            access_token = self._get_auth_token()
            headers = {"Authorization": f"Bearer {access_token}"}
            user_url = f"{self.panel.api_url}/api/user/{username}"

            response = requests.get(user_url, headers=headers, verify=False, timeout=10)
            response.raise_for_status()
            return response.json() # Returns the full user object from Marzban
        except (requests.exceptions.RequestException, ConnectionError) as e:
            print(f"Error getting Marzban user {username}: {e}")
            return None

    async def delete_user(self, username: str) -> bool:
        try:
            access_token = self._get_auth_token()
            headers = {"Authorization": f"Bearer {access_token}"}
            user_url = f"{self.panel.api_url}/api/user/{username}"

            response = requests.delete(user_url, headers=headers, verify=False, timeout=10)
            response.raise_for_status()
            return response.status_code == 200
        except (requests.exceptions.RequestException, ConnectionError) as e:
            print(f"Error deleting Marzban user {username}: {e}")
            return False

    async def modify_user(self, username: str, modifications: Dict) -> bool:
        # This needs to be implemented based on renewal/recharge logic.
        print("Marzban modify_user is not yet implemented.")
        return False


class SanaeiPanel(VpnPanelInterface):
    """Handles all API interactions with a Sanaei panel."""

    def _make_request(self, endpoint: str, params: Optional[Dict] = None) -> Optional[Dict]:
        """Helper function to make requests to the Sanaei API."""
        # In Sanaei, the token is passed as a URL parameter.
        base_url = f"{self.panel.api_url}/{self.panel.api_token}/{endpoint}"
        try:
            response = requests.get(base_url, params=params, timeout=15)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"Sanaei API request failed for endpoint {endpoint}: {e}")
            return None

    async def create_user(self, username: str, plan: Dict) -> Optional[Dict[str, Any]]:
        gb = plan.get('data_limit_gb', 0)
        days = plan.get('duration_days', 0)
        
        # Sanaei API uses 'add' endpoint with specific parameters
        # Example: /token/add/format/json/name/test/traffic/10/day/30
        endpoint = f"add/format/json/name/{username}/traffic/{gb}/day/{days}"
        
        response = self._make_request(endpoint)
        
        if response and response.get('ok', False) and response.get('result'):
            result = response['result']
            return {
                "username": username,
                "subscription_url": result.get("sub"),
                "links": [result.get("vless")] if result.get("vless") else []
            }
        print(f"Failed to create Sanaei user. Response: {response}")
        return None

    async def get_user(self, username: str) -> Optional[Dict[str, Any]]:
        # Sanaei API uses 'user' endpoint to get user info by name
        # Example: /token/user/format/json/name/test
        endpoint = f"user/format/json/name/{username}"
        response = self._make_request(endpoint)

        if response and response.get('ok', False) and response.get('result'):
            user_info = response['result']
            # We need to map Sanaei's response to a structure similar to Marzban's
            return {
                "username": user_info.get("name"),
                "used_traffic": user_info.get("usage", 0),
                "data_limit": user_info.get("traffic", 0),
                "expire": user_info.get("expire", 0),
                "subscription_url": user_info.get("sub"),
                "links": [user_info.get("vless")] if user_info.get("vless") else []
            }
        return None

    async def delete_user(self, username: str) -> bool:
        # Sanaei API uses 'delete' endpoint
        # Example: /token/delete/format/json/name/test
        endpoint = f"delete/format/json/name/{username}"
        response = self._make_request(endpoint)
        return response and response.get('ok', False)

    async def modify_user(self, username: str, modifications: Dict) -> bool:
        print("Sanaei modify_user is not yet implemented.")
        return False


# A dictionary mapping panel type strings to their corresponding handler classes.
# This makes it easy to add new panel types in the future.
PANEL_CLASSES = {
    "marzban": MarzbanPanel,
    "sanaei": SanaeiPanel,
    # "pasargard": PasargardPanel, # Add this when implemented
}

def get_panel_handler(panel_details: VpnPanel) -> Optional[VpnPanelInterface]:
    """
    Factory function that returns an instance of the correct panel handler
    based on the panel's type.
    """
    handler_class = PANEL_CLASSES.get(panel_details.panel_type.lower())
    if handler_class:
        return handler_class(panel_details)
    else:
        print(f"Error: No panel handler found for type '{panel_details.panel_type}'")
        return None

