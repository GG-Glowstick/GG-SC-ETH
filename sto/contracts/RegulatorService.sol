pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import 'zeppelin-solidity/contracts/token/ERC20/DetailedERC20.sol';
import './RegulatorServiceI.sol';


contract RegulatorService is RegulatorServiceI, Ownable {
  /**
   * @dev Throws if called by any account other than the admin
   */
  modifier onlyAdmins() {
    require(msg.sender == admin || msg.sender == owner);
    _;
  }

  /// @dev Settings that affect token trading at a global level
  struct Settings {

    /**
     * @dev Toggle for locking/unlocking trades at a token level.
     *      The default behavior of the zero memory state for locking will be unlocked.
     */
    bool locked;

    /**
     * @dev Toggle for allowing/disallowing fractional token trades at a token level.
     *      The default state when this contract is created `false` (or no partial
     *      transfers allowed).
     */
    bool partialTransfers;

    /**
     * @dev Mappning for 12 months hold up period for investors.
     * @param  address investors wallet
     * @param  uint256 holdingPeriod start date in unix
     */
    mapping(address => uint256) holdingPeriod;
  }

  // @dev number of seconds in a year = 365 * 24 * 60 * 60
  uint256 constant private YEAR = 1 years;

  // @dev Check success code & message
  uint8 constant private CHECK_SUCCESS = 0;
  string constant private SUCCESS_MESSAGE = 'Success';

  // @dev Check error reason: Token is locked
  uint8 constant private CHECK_ELOCKED = 1;
  string constant private ELOCKED_MESSAGE = 'Token is locked';

  // @dev Check error reason: Token can not trade partial amounts
  uint8 constant private CHECK_EDIVIS = 2;
  string constant private EDIVIS_MESSAGE = 'Token can not trade partial amounts';

  // @dev Check error reason: Sender is not allowed to send the token
  uint8 constant private CHECK_ESEND = 3;
  string constant private ESEND_MESSAGE = 'Sender is not allowed to send the token';

  // @dev Check error reason: Receiver is not allowed to receive the token
  uint8 constant private CHECK_ERECV = 4;
  string constant private ERECV_MESSAGE = 'Receiver is not allowed to receive the token';

  uint8 constant private CHECK_EHOLDING_PERIOD = 5;
  string constant private EHOLDING_PERIOD_MESSAGE = 'Sender is still in 12 months holding period';

  uint8 constant private CHECK_EDECIMALS = 6;
  string constant private EDECIMALS_MESSAGE = 'Transfer value must be bigger than MINIMAL_TRANSFER';

  uint256 constant public MINIMAL_TRANSFER = 1 wei;

  /// @dev Permission bits for allowing a participant to send tokens
  uint8 constant private PERM_SEND = 0x1;

  /// @dev Permission bits for allowing a participant to receive tokens
  uint8 constant private PERM_RECEIVE = 0x2;

  // @dev Address of the administrator
  address public admin;

  /// @notice Permissions that allow/disallow token trades on a per token level
  mapping(address => Settings) private settings;

  /// @dev Permissions that allow/disallow token trades on a per participant basis.
  ///      The format for key based access is `participants[tokenAddress][participantAddress]`
  ///      which returns the permission bits of a participant for a particular token.
  mapping(address => mapping(address => uint8)) private participants;

  /// @dev Event raised when a token's locked setting is set
  event LogLockSet(address indexed token, bool locked);

  /// @dev Event raised when a token's partial transfer setting is set
  event LogPartialTransferSet(address indexed token, bool enabled);

  /// @dev Event raised when a participant permissions are set for a token
  event LogPermissionSet(address indexed token, address indexed participant, uint8 permission);

  /// @dev Event raised when the admin address changes
  event LogTransferAdmin(address indexed oldAdmin, address indexed newAdmin);

  /// @dev Event raised when holding period start date is set for participant
  event LogHoldingPeriod(
    address indexed _token, address indexed _participant, uint256 _startDate);

  constructor() public {
    admin = msg.sender;
  }

  /**
   * @notice Locks the ability to trade a token
   *
   * @dev    This method can only be called by this contract's owner
   *
   * @param  _token The address of the token to lock
   */
  function setLocked(address _token, bool _locked) onlyOwner public {
    settings[_token].locked = _locked;

    emit LogLockSet(_token, _locked);
  }

  /**
   * @notice Allows the ability to trade a fraction of a token
   *
   * @dev    This method can only be called by this contract's owner
   *
   * @param  _token The address of the token to allow partial transfers
   */
  function setPartialTransfers(address _token, bool _enabled) onlyOwner public {
   settings[_token].partialTransfers = _enabled;

   emit LogPartialTransferSet(_token, _enabled);
  }

  /**
   * @notice Sets the trade permissions for a participant on a token
   *
   * @dev    The `_permission` bits overwrite the previous trade permissions and can
   *         only be called by the contract's owner.  `_permissions` can be bitwise
   *         `|`'d together to allow for more than one permission bit to be set.
   *
   * @param  _token The address of the token
   * @param  _participant The address of the trade participant
   * @param  _permission Permission bits to be set
   */
  function setPermission(address _token, address _participant, uint8 _permission) onlyAdmins public {
    participants[_token][_participant] = _permission;

    emit LogPermissionSet(_token, _participant, _permission);
  }

  /**
   * @notice Set initial holding period for investor
   * @param _token       token address
   * @param _participant participant address
   * @param _startDate   start date of holding period in UNIX format
   */
  function setHoldingPeriod(address _token, address _participant, uint256 _startDate) onlyAdmins public {
    settings[_token].holdingPeriod[_participant] = _startDate;

    emit LogHoldingPeriod(_token, _participant, _startDate);
  }

  /**
   * @dev Allows the owner to transfer admin controls to newAdmin.
   *
   * @param newAdmin The address to transfer admin rights to.
   */
  function transferAdmin(address newAdmin) onlyOwner public {
    require(newAdmin != address(0));

    address oldAdmin = admin;
    admin = newAdmin;

    emit LogTransferAdmin(oldAdmin, newAdmin);
  }

  /**
   * @notice Checks whether or not a trade should be approved
   *
   * @dev    This method calls back to the token contract specified by `_token` for
   *         information needed to enforce trade approval if needed
   *
   * @param  _token The address of the token to be transfered
   * @param  _spender The address of the spender of the token (unused in this implementation)
   * @param  _from The address of the sender account
   * @param  _to The address of the receiver account
   * @param  _amount The quantity of the token to trade
   *
   * @return `true` if the trade should be approved and `false` if the trade should not be approved
   */
  function check(address _token, address _spender, address _from, address _to, uint256 _amount) public returns (uint8) {
    if (settings[_token].locked) {
      return CHECK_ELOCKED;
    }

    if (participants[_token][_from] & PERM_SEND == 0) {
      return CHECK_ESEND;
    }

    if (participants[_token][_to] & PERM_RECEIVE == 0) {
      return CHECK_ERECV;
    }

    if (!settings[_token].partialTransfers && _amount % _wholeToken(_token) != 0) {
      return CHECK_EDIVIS;
    }

    if (settings[_token].holdingPeriod[_from] + YEAR >= now) {
      return CHECK_EHOLDING_PERIOD;
    }

    if (_amount < MINIMAL_TRANSFER) {
      return CHECK_EDECIMALS;
    }

    return CHECK_SUCCESS;
  }

  /**
   * @notice Returns the error message for a passed failed check reason
   *
   * @param  _reason The reason code: 0 means success.  Non-zero values are left to the implementation
   *                 to assign meaning.
   *
   * @return The human-readable mesage string
   */
  function messageForReason (uint8 _reason) public pure returns (string) {
    if (_reason == CHECK_ELOCKED) {
      return ELOCKED_MESSAGE;
    }

    if (_reason == CHECK_ESEND) {
      return ESEND_MESSAGE;
    }

    if (_reason == CHECK_ERECV) {
      return ERECV_MESSAGE;
    }

    if (_reason == CHECK_EDIVIS) {
      return EDIVIS_MESSAGE;
    }

    if (_reason == CHECK_EHOLDING_PERIOD) {
      return EHOLDING_PERIOD_MESSAGE;
    }

    if (_reason == CHECK_EDECIMALS) {
      return EDECIMALS_MESSAGE;
    }

    return SUCCESS_MESSAGE;
  }

  /**
   * @notice Retrieves the whole token value from a token that this `RegulatorService` manages
   *
   * @param  _token The token address of the managed token
   *
   * @return The uint256 value that represents a single whole token
   */
  function _wholeToken(address _token) view private returns (uint256) {
    return uint256(10)**DetailedERC20(_token).decimals();
  }
}
